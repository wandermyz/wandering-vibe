import Foundation

/// User-tunable settings, persisted in UserDefaults.
final class AppSettings: ObservableObject {
    static let capChoices = [100_000, 250_000, 500_000, 1_000_000, 2_000_000]
    static let timeoutChoices: [Double] = [2, 3, 4, 6, 8]

    /// Fixed cadence: probe every `interval` seconds or every `distance` metres, whichever comes first.
    static let interval: TimeInterval = 5
    static let distance: Double = 10
    /// Fixes worse than this are not recorded.
    static let maxHorizontalAccuracy: Double = 100

    @Published var probeURL: String { didSet { defaults.set(probeURL, forKey: "probeURL") } }
    @Published var timeout: Double { didSet { defaults.set(timeout, forKey: "timeout") } }
    @Published var maxPoints: Int { didSet { defaults.set(maxPoints, forKey: "maxPoints") } }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        probeURL = defaults.string(forKey: "probeURL") ?? "https://www.gstatic.com/generate_204"
        timeout = defaults.object(forKey: "timeout") as? Double ?? 4
        maxPoints = defaults.object(forKey: "maxPoints") as? Int ?? 500_000
    }

    /// Host and path of `probeURL`, falling back to the default when unparsable.
    var probeTarget: (host: String, path: String) {
        if let u = URL(string: probeURL), u.scheme == "https", let host = u.host, !host.isEmpty {
            let path = u.path.isEmpty ? "/" : u.path
            return (host, u.query.map { "\(path)?\($0)" } ?? path)
        }
        return ("www.gstatic.com", "/generate_204")
    }
}
