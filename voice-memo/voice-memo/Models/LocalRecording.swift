import Foundation

/// A recording stored locally on the device. The sidecar JSON next to the audio file is the source
/// of truth for date/location/duration so we never have to parse the m4a back.
struct LocalRecording: Identifiable, Codable, Equatable {
    let id: UUID
    var filename: String         // e.g. "2026-05-20 1432 San Francisco.m4a"
    var createdAt: Date
    var duration: TimeInterval
    var location: String?
    var uploadedAt: Date?        // nil until successfully uploaded
    var driveFileID: String?

    var audioFileName: String { "\(id.uuidString).m4a" }
    var sidecarFileName: String { "\(id.uuidString).json" }

    var monthFolderName: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMM"
        return f.string(from: createdAt)
    }
}

@MainActor
final class LocalRecordingsStore: ObservableObject {
    @Published private(set) var recordings: [LocalRecording] = []
    private let dir: URL

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.dir = docs.appendingPathComponent("recordings", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        reload()
    }

    var directory: URL { dir }

    func audioURL(for rec: LocalRecording) -> URL { dir.appendingPathComponent(rec.audioFileName) }
    func sidecarURL(for rec: LocalRecording) -> URL { dir.appendingPathComponent(rec.sidecarFileName) }

    func reload() {
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        let sidecars = files.filter { $0.pathExtension == "json" }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var loaded: [LocalRecording] = []
        for url in sidecars {
            if let data = try? Data(contentsOf: url),
               let rec = try? decoder.decode(LocalRecording.self, from: data) {
                loaded.append(rec)
            }
        }
        self.recordings = loaded.sorted(by: { $0.createdAt > $1.createdAt })
    }

    /// Build filename in the iOS-Voice-Memos pattern: `yyyy-MM-dd HHmm [Location].m4a`.
    static func makeFilename(date: Date, location: String?) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd HHmm"
        let stamp = df.string(from: date)
        if let location, !location.isEmpty {
            let clean = location.replacingOccurrences(of: "/", with: "-")
            return "\(stamp) \(clean).m4a"
        }
        return "\(stamp).m4a"
    }

    @discardableResult
    func save(_ recording: LocalRecording) throws -> LocalRecording {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(recording)
        try data.write(to: sidecarURL(for: recording), options: .atomic)
        reload()
        return recording
    }

    func markUploaded(_ recording: LocalRecording, driveFileID: String, at: Date = Date()) throws {
        var r = recording
        r.uploadedAt = at
        r.driveFileID = driveFileID
        try save(r)
    }

    func delete(_ recording: LocalRecording) {
        try? FileManager.default.removeItem(at: audioURL(for: recording))
        try? FileManager.default.removeItem(at: sidecarURL(for: recording))
        reload()
    }
}
