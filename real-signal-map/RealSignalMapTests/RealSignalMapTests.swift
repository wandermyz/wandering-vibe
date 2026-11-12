import XCTest
@testable import RealSignalMap

final class SampleStoreTests: XCTestCase {
    private func tempStore() throws -> SampleStore {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
        return try SampleStore(url: url)
    }

    private func sample(_ i: Int, rtt: Int? = 100, status: ProbeStatus = .ok, session: Int64 = 1) -> Sample {
        Sample(ts: Date(timeIntervalSince1970: 1_700_000_000 + Double(i)), lat: 37 + Double(i) * 1e-4, lon: -122,
               hAcc: 5, speed: 10, rttMs: rtt, setupMs: nil, status: status, radio: .lte, session: session)
    }

    func testRoundTrip() throws {
        let store = try tempStore()
        store.insert([sample(0), sample(1, rtt: nil, status: .timeout)], cap: 100)
        let rows = store.samples(from: .distantPast, to: .distantFuture, minLat: -90, maxLat: 90, minLon: -180, maxLon: 180)
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].rttMs, 100)
        XCTAssertNil(rows[1].rttMs)
        XCTAssertEqual(rows[1].status, .timeout)
        XCTAssertEqual(rows[1].radio, .lte)
    }

    func testEvictsOldestBeyondCapWithSlack() throws {
        let store = try tempStore()
        // 1% slack on cap 100 → no eviction at 101.
        store.insert((0..<101).map { sample($0) }, cap: 100)
        XCTAssertEqual(store.stats().count, 101)
        // Crossing the slack trims back to exactly the cap, dropping the oldest.
        store.insert((101..<110).map { sample($0) }, cap: 100)
        XCTAssertEqual(store.stats().count, 100)
        let rows = store.samples(from: .distantPast, to: .distantFuture, minLat: -90, maxLat: 90, minLon: -180, maxLon: 180)
        XCTAssertEqual(rows.first?.ts, sample(10).ts)
        XCTAssertEqual(rows.last?.ts, sample(109).ts)
    }

    func testEnforceCapAndTimeQuery() throws {
        let store = try tempStore()
        store.insert((0..<50).map { sample($0) }, cap: 1000)
        store.enforceCap(20)
        XCTAssertEqual(store.stats().count, 20)
        let rows = store.samples(from: sample(40).ts, to: sample(44).ts, minLat: -90, maxLat: 90, minLon: -180, maxLon: 180)
        XCTAssertEqual(rows.count, 5)
        XCTAssertEqual(store.histogram(bucket: 10).values.reduce(0, +), 20)
    }
}

final class AggregationTests: XCTestCase {
    private func s(_ rtt: Int?, session: Int64 = 1, t: Double = 0, lat: Double = 37) -> Sample {
        Sample(ts: Date(timeIntervalSince1970: t), lat: lat, lon: -122, hAcc: 5, speed: 0, rttMs: rtt, setupMs: nil,
               status: rtt == nil ? .timeout : .ok, radio: .lte, session: session)
    }

    func testStats() {
        let st = SpotStats(samples: [s(100), s(300), s(nil), s(200, session: 2), s(150, session: 2)])
        XCTAssertEqual(st.count, 5)
        XCTAssertEqual(st.failures, 1)
        XCTAssertEqual(st.median, 150)
        XCTAssertEqual(st.worst, 300)
        XCTAssertEqual(st.sessions.count, 2)
        XCTAssertEqual(st.passes.count, 2)
        // Jitter: |300-100| = 200 (session 1), |150-200| = 50 (session 2) → mean 125.
        XCTAssertEqual(st.jitterMs, 125)
        XCTAssertEqual(st.passes[0], [100, 300, nil])
    }

    func testMostlyDeadCellIsPurple() {
        let st = SpotStats(samples: [s(100), s(nil), s(nil)])
        XCTAssertEqual(st.color(for: .median), LatencyScale.purple)
        XCTAssertEqual(SpotStats(samples: [s(100), s(120)]).color(for: .median), LatencyScale.green)
    }

    func testGridAndSegments() {
        let samples = [s(100, t: 0, lat: 37.0), s(100, t: 5, lat: 37.0002), s(100, t: 100, lat: 37.0004), s(100, session: 2, t: 105, lat: 37.0006)]
        let g = Aggregation.grid(samples, cellMeters: 1000, refLat: 37)
        XCTAssertEqual(g.cells.values.reduce(0) { $0 + $1.count }, 4)
        let segs = Aggregation.segments(samples)
        XCTAssertEqual(segs.count, 4)
        XCTAssertNotEqual(segs[0].a.y, segs[0].b.y) // joined to next
        XCTAssertEqual(segs[1].a.y, segs[1].b.y)    // 95 s gap → not joined
        XCTAssertEqual(segs[2].a.y, segs[2].b.y)    // next is a different session
        XCTAssertEqual(Aggregation.cellSize(forMapWidth: 10_000), 500)
    }
}

final class HTTPParserTests: XCTestCase {
    func testParse() {
        XCTAssertEqual(HTTPResponseParser.parse(Data("HTTP/1.1 204 No Content\r\nContent-Length: 0\r\n".utf8)), .incomplete)
        XCTAssertEqual(HTTPResponseParser.parse(Data("HTTP/1.1 204 No Content\r\nContent-Length: 0\r\n\r\n".utf8)), .complete(status: 204))
        XCTAssertEqual(HTTPResponseParser.parse(Data("HTTP/1.1 200 OK\r\nContent-Length: 4\r\n\r\nab".utf8)), .incomplete)
        XCTAssertEqual(HTTPResponseParser.parse(Data("HTTP/1.1 200 OK\r\nContent-Length: 4\r\n\r\nabcd".utf8)), .complete(status: 200))
        XCTAssertEqual(HTTPResponseParser.parse(Data("HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n2\r\nhi\r\n0\r\n\r\n".utf8)), .complete(status: 200))
        XCTAssertEqual(HTTPResponseParser.parse(Data("garbage\r\n\r\n".utf8)), .invalid)
    }
}
