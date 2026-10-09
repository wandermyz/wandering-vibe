import Foundation

enum DriveError: Error {
    case httpFailure(Int, String)
    case malformedResponse
}

actor DriveClient {
    typealias TokenProvider = @Sendable () async throws -> String

    private let tokenProvider: TokenProvider
    private var folderCache: [String: String] = [:]
    private let session: URLSession

    init(tokenProvider: @escaping TokenProvider, session: URLSession = .shared) {
        self.tokenProvider = tokenProvider
        self.session = session
    }

    // MARK: - Folder ensure

    func ensureFolder(named name: String, parent: String) async throws -> String {
        let key = "\(parent)/\(name)"
        if let id = folderCache[key] { return id }
        if let id = try await findFolder(named: name, parent: parent) {
            folderCache[key] = id
            return id
        }
        let id = try await createFolder(named: name, parent: parent)
        folderCache[key] = id
        return id
    }

    private func findFolder(named name: String, parent: String) async throws -> String? {
        let q = "mimeType='application/vnd.google-apps.folder' and name='\(escape(name))' and '\(escape(parent))' in parents and trashed=false"
        var comps = URLComponents(string: "https://www.googleapis.com/drive/v3/files")!
        comps.queryItems = [
            URLQueryItem(name: "q", value: q),
            URLQueryItem(name: "fields", value: "files(id,name)"),
            URLQueryItem(name: "pageSize", value: "1"),
        ]
        let data = try await get(comps.url!)
        struct Resp: Decodable { struct F: Decodable { let id: String }; let files: [F] }
        return try JSONDecoder().decode(Resp.self, from: data).files.first?.id
    }

    private func createFolder(named name: String, parent: String) async throws -> String {
        var req = try await authed(URL(string: "https://www.googleapis.com/drive/v3/files")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "name": name,
            "mimeType": "application/vnd.google-apps.folder",
            "parents": [parent],
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await session.data(for: req)
        try check(resp, data)
        struct Resp: Decodable { let id: String }
        return try JSONDecoder().decode(Resp.self, from: data).id
    }

    // MARK: - Upload

    func upload(
        fileURL: URL,
        name: String,
        parent: String,
        createdAt: Date,
        durationSec: Double?
    ) async throws -> String {
        let boundary = "vmboundary-\(UUID().uuidString)"
        var meta: [String: Any] = [
            "name": name,
            "parents": [parent],
            "createdTime": Self.rfc3339.string(from: createdAt),
            "modifiedTime": Self.rfc3339.string(from: createdAt),
        ]
        if let durationSec {
            meta["appProperties"] = ["durationSec": String(format: "%.3f", durationSec)]
        }
        let metaJSON = try JSONSerialization.data(withJSONObject: meta)
        let audio = try Data(contentsOf: fileURL)

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/json; charset=UTF-8\r\n\r\n".data(using: .utf8)!)
        body.append(metaJSON)
        body.append("\r\n--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/m4a\r\n\r\n".data(using: .utf8)!)
        body.append(audio)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        let url = URL(string: "https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart&fields=id")!
        var req = try await authed(url)
        req.httpMethod = "POST"
        req.setValue("multipart/related; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        let (data, resp) = try await session.data(for: req)
        try check(resp, data)
        struct Resp: Decodable { let id: String }
        return try JSONDecoder().decode(Resp.self, from: data).id
    }

    // MARK: - List

    /// Returns the set of filenames present in `parent`. Used to compute the upload diff.
    func filenames(in parent: String) async throws -> Set<String> {
        let q = "'\(escape(parent))' in parents and trashed=false"
        var comps = URLComponents(string: "https://www.googleapis.com/drive/v3/files")!
        comps.queryItems = [
            URLQueryItem(name: "q", value: q),
            URLQueryItem(name: "fields", value: "files(id,name,mimeType)"),
            URLQueryItem(name: "pageSize", value: "1000"),
        ]
        let data = try await get(comps.url!)
        struct Resp: Decodable {
            struct F: Decodable { let name: String; let mimeType: String? }
            let files: [F]
        }
        let r = try JSONDecoder().decode(Resp.self, from: data)
        return Set(r.files.filter { $0.mimeType != "application/vnd.google-apps.folder" }.map { $0.name })
    }

    // MARK: - Internals

    private func get(_ url: URL) async throws -> Data {
        let req = try await authed(url)
        let (data, resp) = try await session.data(for: req)
        try check(resp, data)
        return data
    }

    private func authed(_ url: URL) async throws -> URLRequest {
        var req = URLRequest(url: url)
        let token = try await tokenProvider()
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return req
    }

    private func check(_ resp: URLResponse, _ data: Data) throws {
        guard let http = resp as? HTTPURLResponse else { throw DriveError.malformedResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw DriveError.httpFailure(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
    }

    private func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "'", with: "\\'")
    }

    private static let rfc3339: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}
