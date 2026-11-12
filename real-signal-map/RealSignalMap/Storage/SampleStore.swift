import Foundation
import SQLite3

/// Append-only SQLite store of samples, capped as a ring buffer.
///
/// Rows are only ever deleted as a prefix of the primary key (oldest first) or all at once,
/// so `id`s stay contiguous and the row count is simply `maxId - minId + 1`.
/// All access is serialized on a private queue; the class is safe to share across threads.
final class SampleStore: @unchecked Sendable {
    static let shared = try! SampleStore(url: SampleStore.defaultURL)

    static var defaultURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("samples.sqlite")
    }

    /// Eviction kicks in once the count exceeds cap by this fraction, then trims back to cap.
    static let evictionSlack = 0.01

    private let queue = DispatchQueue(label: "SampleStore")
    private var db: OpaquePointer?
    let url: URL

    init(url: URL) throws {
        self.url = url
        guard sqlite3_open(url.path, &db) == SQLITE_OK else {
            throw StoreError.sqlite(String(cString: sqlite3_errmsg(db)))
        }
        try exec("PRAGMA journal_mode=WAL")
        try exec("PRAGMA synchronous=NORMAL")
        try exec("""
            CREATE TABLE IF NOT EXISTS sample (
              id       INTEGER PRIMARY KEY,
              ts       INTEGER NOT NULL,
              lat      REAL    NOT NULL,
              lon      REAL    NOT NULL,
              h_acc    REAL,
              speed    REAL,
              rtt_ms   INTEGER,
              setup_ms INTEGER,
              status   INTEGER NOT NULL,
              radio    INTEGER,
              session  INTEGER NOT NULL
            )
            """)
        try exec("CREATE INDEX IF NOT EXISTS sample_ts ON sample(ts)")
    }

    deinit { sqlite3_close(db) }

    enum StoreError: Error { case sqlite(String) }

    // MARK: Writes

    /// Inserts a batch in one transaction, then trims the oldest rows if over `cap`.
    func insert(_ samples: [Sample], cap: Int) {
        guard !samples.isEmpty else { return }
        queue.sync {
            do {
                try exec("BEGIN")
                let stmt = try prepare("""
                    INSERT INTO sample (ts, lat, lon, h_acc, speed, rtt_ms, setup_ms, status, radio, session)
                    VALUES (?,?,?,?,?,?,?,?,?,?)
                    """)
                defer { sqlite3_finalize(stmt) }
                for s in samples {
                    sqlite3_reset(stmt)
                    sqlite3_bind_int64(stmt, 1, Int64(s.ts.timeIntervalSince1970 * 1000))
                    sqlite3_bind_double(stmt, 2, s.lat)
                    sqlite3_bind_double(stmt, 3, s.lon)
                    sqlite3_bind_double(stmt, 4, s.hAcc)
                    sqlite3_bind_double(stmt, 5, s.speed)
                    bindOptional(stmt, 6, s.rttMs)
                    bindOptional(stmt, 7, s.setupMs)
                    sqlite3_bind_int(stmt, 8, Int32(s.status.rawValue))
                    sqlite3_bind_int(stmt, 9, Int32(s.radio.rawValue))
                    sqlite3_bind_int64(stmt, 10, s.session)
                    guard sqlite3_step(stmt) == SQLITE_DONE else { throw lastError() }
                }
                try evictLocked(cap: cap)
                try exec("COMMIT")
            } catch {
                try? exec("ROLLBACK")
                NSLog("SampleStore insert failed: \(error)")
            }
        }
    }

    /// Trims to `cap` immediately (used when the user lowers the cap).
    func enforceCap(_ cap: Int) {
        queue.sync { try? evictLocked(cap: cap, slack: 0) }
    }

    func deleteAll() {
        queue.sync {
            try? exec("DELETE FROM sample")
            try? exec("VACUUM")
        }
    }

    private func evictLocked(cap: Int, slack: Double = SampleStore.evictionSlack) throws {
        let (minId, maxId) = idRangeLocked()
        guard let minId, let maxId else { return }
        let count = maxId - minId + 1
        guard Double(count) > Double(cap) * (1 + slack) else { return }
        try exec("DELETE FROM sample WHERE id <= \(maxId - Int64(cap))")
    }

    // MARK: Reads

    struct Stats: Sendable { var count: Int; var oldest: Date?; var bytes: Int64 }

    func stats() -> Stats {
        queue.sync {
            let (minId, maxId) = idRangeLocked()
            let count = minId.flatMap { lo in maxId.map { Int($0 - lo + 1) } } ?? 0
            var oldest: Date?
            if let minId { oldest = scalarLocked("SELECT ts FROM sample WHERE id = \(minId)").map(Self.date) }
            let files = [url.path, url.path + "-wal"]
            let bytes = files.compactMap { try? FileManager.default.attributesOfItem(atPath: $0)[.size] as? Int64 }.reduce(0, +)
            return Stats(count: count, oldest: oldest, bytes: bytes)
        }
    }

    func timeBounds() -> ClosedRange<Date>? {
        queue.sync {
            guard let lo = scalarLocked("SELECT min(ts) FROM sample"),
                  let hi = scalarLocked("SELECT max(ts) FROM sample") else { return nil }
            return Self.date(lo)...Self.date(hi)
        }
    }

    /// Position of the most recent sample, used to open the History map somewhere useful.
    func latestCoordinate() -> (lat: Double, lon: Double)? {
        queue.sync {
            guard let stmt = try? prepare("SELECT lat, lon FROM sample ORDER BY id DESC LIMIT 1") else { return nil }
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
            return (sqlite3_column_double(stmt, 0), sqlite3_column_double(stmt, 1))
        }
    }

    /// Number of samples per `bucket`-sized time slot (keys are slot start times).
    func histogram(bucket: TimeInterval) -> [Date: Int] {
        queue.sync {
            let b = Int64(bucket * 1000)
            var out: [Date: Int] = [:]
            guard let stmt = try? prepare("SELECT ts / \(b), count(*) FROM sample GROUP BY 1") else { return out }
            defer { sqlite3_finalize(stmt) }
            while sqlite3_step(stmt) == SQLITE_ROW {
                out[Self.date(sqlite3_column_int64(stmt, 0) * b)] = Int(sqlite3_column_int(stmt, 1))
            }
            return out
        }
    }

    /// Samples in a time range and lat/lon box, ordered by session then time.
    func samples(from: Date, to: Date, minLat: Double, maxLat: Double, minLon: Double, maxLon: Double,
                 limit: Int = 600_000) -> [Sample] {
        queue.sync {
            var out: [Sample] = []
            guard let stmt = try? prepare("""
                SELECT id, ts, lat, lon, h_acc, speed, rtt_ms, setup_ms, status, radio, session FROM sample
                WHERE ts BETWEEN ? AND ? AND lat BETWEEN ? AND ? AND lon BETWEEN ? AND ?
                ORDER BY session, ts LIMIT ?
                """) else { return out }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_int64(stmt, 1, Int64(from.timeIntervalSince1970 * 1000))
            sqlite3_bind_int64(stmt, 2, Int64(to.timeIntervalSince1970 * 1000))
            sqlite3_bind_double(stmt, 3, minLat)
            sqlite3_bind_double(stmt, 4, maxLat)
            sqlite3_bind_double(stmt, 5, minLon)
            sqlite3_bind_double(stmt, 6, maxLon)
            sqlite3_bind_int64(stmt, 7, Int64(limit))
            while sqlite3_step(stmt) == SQLITE_ROW {
                out.append(Sample(
                    id: sqlite3_column_int64(stmt, 0),
                    ts: Self.date(sqlite3_column_int64(stmt, 1)),
                    lat: sqlite3_column_double(stmt, 2),
                    lon: sqlite3_column_double(stmt, 3),
                    hAcc: sqlite3_column_double(stmt, 4),
                    speed: sqlite3_column_double(stmt, 5),
                    rttMs: optionalInt(stmt, 6),
                    setupMs: optionalInt(stmt, 7),
                    status: ProbeStatus(rawValue: Int(sqlite3_column_int(stmt, 8))) ?? .error,
                    radio: Radio(rawValue: Int(sqlite3_column_int(stmt, 9))) ?? .unknown,
                    session: sqlite3_column_int64(stmt, 10)))
            }
            return out
        }
    }

    // MARK: Helpers (call on queue)

    private static func date(_ ms: Int64) -> Date { Date(timeIntervalSince1970: Double(ms) / 1000) }

    private func idRangeLocked() -> (Int64?, Int64?) {
        (scalarLocked("SELECT min(id) FROM sample"), scalarLocked("SELECT max(id) FROM sample"))
    }

    private func scalarLocked(_ sql: String) -> Int64? {
        guard let stmt = try? prepare(sql) else { return nil }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW, sqlite3_column_type(stmt, 0) != SQLITE_NULL else { return nil }
        return sqlite3_column_int64(stmt, 0)
    }

    private func exec(_ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw lastError() }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { throw lastError() }
        return stmt
    }

    private func lastError() -> StoreError { .sqlite(String(cString: sqlite3_errmsg(db))) }

    private func bindOptional(_ stmt: OpaquePointer?, _ idx: Int32, _ v: Int?) {
        if let v { sqlite3_bind_int64(stmt, idx, Int64(v)) } else { sqlite3_bind_null(stmt, idx) }
    }

    private func optionalInt(_ stmt: OpaquePointer?, _ idx: Int32) -> Int? {
        sqlite3_column_type(stmt, idx) == SQLITE_NULL ? nil : Int(sqlite3_column_int64(stmt, idx))
    }
}
