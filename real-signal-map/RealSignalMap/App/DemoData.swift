#if DEBUG
import Foundation

/// Synthetic drives for simulator screenshots: launch with `-seedDemo`.
enum DemoData {
    static func seedIfRequested(into store: SampleStore) {
        guard ProcessInfo.processInfo.arguments.contains("-seedDemo"), store.stats().count == 0 else { return }
        var rng = SystemRandomNumberGenerator()
        var out: [Sample] = []
        let now = Date()
        // A highway-ish route through the Santa Cruz mountains, driven twice a day for 10 days.
        let a = (lat: 37.3230, lon: -122.0322), b = (lat: 36.9741, lon: -122.0308)
        for day in 0..<10 {
            for leg in 0..<2 {
                let start = Calendar.current.startOfDay(for: now).addingTimeInterval(Double(-day) * 86_400 + (leg == 0 ? 8.5 : 18) * 3600)
                guard start < now else { continue }
                let session = Int64(start.timeIntervalSince1970 * 1000)
                let n = 500
                for i in 0..<n {
                    var t = Double(i) / Double(n - 1)
                    if leg == 1 { t = 1 - t }
                    let wiggle = 0.012 * sin(t * 18)
                    let lat = a.lat + (b.lat - a.lat) * t
                    let lon = a.lon + (b.lon - a.lon) * t + wiggle - 0.03 * sin(t * .pi)
                    var rtt: Int? = Int.random(in: 45...140, using: &rng)
                    var radio = Radio.nr5gNSA
                    if t > 0.38 && t < 0.52 {           // the summit dead zone
                        radio = .lte
                        rtt = Double.random(in: 0...1, using: &rng) < 0.35 ? nil : Int.random(in: 600...2600, using: &rng)
                    } else if t > 0.28 && t < 0.6 {
                        radio = .lte
                        rtt = Int.random(in: 180...700, using: &rng)
                    }
                    out.append(Sample(ts: start.addingTimeInterval(Double(i) * 5), lat: lat, lon: lon, hAcc: 5, speed: 25,
                                      rttMs: rtt, setupMs: nil, status: rtt == nil ? .timeout : .ok,
                                      radio: radio, session: session))
                }
            }
        }
        out.sort { $0.ts < $1.ts }
        store.insert(out, cap: 500_000)
    }
}
#endif
