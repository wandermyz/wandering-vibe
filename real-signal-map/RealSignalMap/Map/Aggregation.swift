import CoreLocation
import MapKit
import UIKit

/// What a cell's colour represents in the History map.
enum Metric: String, CaseIterable, Identifiable {
    case median = "Median", p90 = "P90", worst = "Worst", failRate = "Fail %"
    var id: String { rawValue }
}

/// Statistics for a set of samples (a grid cell, or the samples near a tapped spot).
struct SpotStats {
    var count = 0
    var failures = 0
    /// Sorted successful round-trips.
    var rtts: [Int] = []
    var sessions: Set<Int64> = []
    var radios: [Radio: Int] = [:]
    var lastSeen: Date?
    /// Mean absolute difference between consecutive RTTs within a session (video-call jitter proxy).
    var jitterMs: Int?
    /// Per-session latency strips (nil = failure), oldest session first, for the detail view.
    var passes: [[Int?]] = []

    var failRate: Double { count == 0 ? 0 : Double(failures) / Double(count) }
    var median: Int? { percentile(0.5) }
    var p90: Int? { percentile(0.9) }
    var worst: Int? { rtts.last }

    func percentile(_ p: Double) -> Int? {
        guard !rtts.isEmpty else { return nil }
        let idx = min(rtts.count - 1, max(0, Int((Double(rtts.count) * p).rounded(.up)) - 1))
        return rtts[idx]
    }

    /// Colour for a metric. Spots that are mostly dead show as "no internet" regardless.
    func color(for metric: Metric) -> UIColor {
        switch metric {
        case .failRate: return LatencyScale.color(failRate: failRate)
        case .median, .p90:
            if failRate > 0.25 { return LatencyScale.purple }
            return LatencyScale.color(ms: metric == .median ? median : p90)
        case .worst:
            return failures > 0 ? LatencyScale.purple : LatencyScale.color(ms: worst)
        }
    }

    /// Builds stats from samples ordered by (session, ts).
    init(samples: some Sequence<Sample>) {
        var lastSession: Int64?
        var lastRtt: Int?
        var diffs: [Int] = []
        for s in samples {
            count += 1
            if s.status.isFailure { failures += 1 }
            if let r = s.rttMs { rtts.append(r) }
            sessions.insert(s.session)
            radios[s.radio, default: 0] += 1
            if lastSeen.map({ s.ts > $0 }) ?? true { lastSeen = s.ts }
            if s.session != lastSession {
                passes.append([])
                lastSession = s.session
                lastRtt = nil
            }
            passes[passes.count - 1].append(s.status.isFailure ? nil : s.rttMs)
            if let r = s.rttMs {
                if let prev = lastRtt { diffs.append(abs(r - prev)) }
                lastRtt = r
            }
        }
        rtts.sort()
        if !diffs.isEmpty { jitterMs = diffs.reduce(0, +) / diffs.count }
    }

    init() {}
}

/// Pure helpers that turn samples into map-ready shapes.
enum Aggregation {
    /// Square grid cell size (metres) for a visible map width, aiming for ~45 cells across.
    static func cellSize(forMapWidth meters: Double) -> Double {
        let steps: [Double] = [25, 50, 100, 200, 500, 1_000, 2_000, 5_000, 10_000, 20_000, 50_000]
        let target = meters / 45
        return steps.first(where: { $0 >= target }) ?? steps.last!
    }

    /// Below this visible width the History map shows raw traces instead of cells.
    static let rawTraceMaxWidth: Double = 3_000

    struct CellKey: Hashable { var x: Int; var y: Int }

    struct Grid {
        var cellMeters: Double
        var dLat: Double
        var dLon: Double
        var cells: [CellKey: [Sample]]

        func key(for c: CLLocationCoordinate2D) -> CellKey {
            CellKey(x: Int((c.longitude / dLon).rounded(.down)), y: Int((c.latitude / dLat).rounded(.down)))
        }

        func bounds(of k: CellKey) -> (minLat: Double, minLon: Double, maxLat: Double, maxLon: Double) {
            (Double(k.y) * dLat, Double(k.x) * dLon, Double(k.y + 1) * dLat, Double(k.x + 1) * dLon)
        }
    }

    /// Buckets samples into a grid of roughly `cellMeters` squares around `refLat`.
    static func grid(_ samples: [Sample], cellMeters: Double, refLat: Double) -> Grid {
        let dLat = cellMeters / 111_320
        let dLon = cellMeters / (111_320 * max(0.05, cos(refLat * .pi / 180)))
        var g = Grid(cellMeters: cellMeters, dLat: dLat, dLon: dLon, cells: [:])
        for s in samples { g.cells[g.key(for: s.coordinate), default: []].append(s) }
        return g
    }

    /// Consecutive samples are joined if they're from the same session and close in time and space.
    static func segments(_ samples: [Sample], maxGap: TimeInterval = 30, maxMeters: Double = 300) -> [TraceSegment] {
        var out: [TraceSegment] = []
        out.reserveCapacity(samples.count)
        for (i, s) in samples.enumerated() {
            let a = MKMapPoint(s.coordinate)
            var b = a
            if i + 1 < samples.count {
                let n = samples[i + 1]
                let nb = MKMapPoint(n.coordinate)
                if n.session == s.session, n.ts.timeIntervalSince(s.ts) <= maxGap, a.distance(to: nb) <= maxMeters {
                    b = nb
                }
            }
            out.append(TraceSegment(a: a, b: b, color: LatencyScale.color(ms: s.status.isFailure ? nil : s.rttMs)))
        }
        return out
    }
}
