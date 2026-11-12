import CoreLocation
import UIKit

/// Outcome of a single connectivity probe.
enum ProbeStatus: Int, Sendable {
    case ok = 0
    /// No response within the timeout.
    case timeout = 1
    /// Connection reset, TLS failure, unexpected response, etc.
    case error = 2
    /// The cellular interface was unavailable (no path at all).
    case noPath = 3

    var isFailure: Bool { self != .ok }
}

/// Radio access technology reported by CoreTelephony at probe time.
enum Radio: Int, Sendable, CaseIterable {
    case unknown = 0, g2 = 1, g3 = 2, lte = 3, nr5gNSA = 4, nr5gSA = 5

    var label: String {
        switch self {
        case .unknown: return "?"
        case .g2: return "2G"
        case .g3: return "3G"
        case .lte: return "LTE"
        case .nr5gNSA: return "5G"
        case .nr5gSA: return "5G SA"
        }
    }
}

/// One stored data point: where we were, when, and whether the internet answered.
struct Sample: Sendable, Equatable {
    var id: Int64 = 0
    var ts: Date
    var lat: Double
    var lon: Double
    var hAcc: Double
    var speed: Double
    /// Round-trip of the probe request on an established connection. nil when failed.
    var rttMs: Int?
    /// Connection establishment time (DNS+TCP+TLS) when this probe had to (re)connect.
    var setupMs: Int?
    var status: ProbeStatus
    var radio: Radio
    /// Recording session (one per foreground stint), unix ms of its start.
    var session: Int64

    var coordinate: CLLocationCoordinate2D { .init(latitude: lat, longitude: lon) }
}

/// Shared latency → colour scale used on the map, legend and sparklines.
enum LatencyScale {
    static let bands: [(limit: Int, label: String)] = [(150, "<150"), (400, "<400"), (1000, "<1s"), (Int.max, "≥1s")]

    static let green = UIColor(red: 0.13, green: 0.77, blue: 0.37, alpha: 1)
    static let yellow = UIColor(red: 0.92, green: 0.70, blue: 0.03, alpha: 1)
    static let orange = UIColor(red: 0.98, green: 0.45, blue: 0.09, alpha: 1)
    static let red = UIColor(red: 0.94, green: 0.27, blue: 0.27, alpha: 1)
    static let purple = UIColor(red: 0.49, green: 0.23, blue: 0.93, alpha: 1)

    /// nil latency means "no internet".
    static func color(ms: Int?) -> UIColor {
        guard let ms else { return purple }
        if ms < 150 { return green }
        if ms < 400 { return yellow }
        if ms < 1000 { return orange }
        return red
    }

    /// Colour for a fail-rate (0…1) view.
    static func color(failRate: Double) -> UIColor {
        if failRate < 0.02 { return green }
        if failRate < 0.10 { return yellow }
        if failRate < 0.25 { return orange }
        return purple
    }

    static func format(ms: Int?) -> String {
        guard let ms else { return "—" }
        return ms >= 1000 ? String(format: "%.1f s", Double(ms) / 1000) : "\(ms) ms"
    }
}
