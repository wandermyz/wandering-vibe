import Foundation
import Network

/// Result of one probe.
struct ProbeResult: Sendable {
    var status: ProbeStatus
    var rttMs: Int?
    /// Set when this probe had to open a new connection.
    var setupMs: Int?
}

/// Probes the internet over the cellular radio using a kept-alive HTTPS connection.
///
/// A connection is opened with `requiredInterfaceType = .cellular` (so Wi-Fi is never used),
/// and each probe sends `GET <path>` over it, timing request → full response headers.
/// That isolates the link's round-trip (what a video call feels) from connection setup,
/// which is recorded separately whenever the connection has to be (re)built.
/// Not thread-safe: call `probe()` from one task at a time (the Recorder guarantees this).
final class Prober: @unchecked Sendable {
    let host: String
    let path: String
    let timeout: TimeInterval

    private let queue = DispatchQueue(label: "Prober")
    private var connection: NWConnection?

    init(host: String, path: String, timeout: TimeInterval) {
        self.host = host
        self.path = path
        self.timeout = timeout
    }

    deinit { connection?.cancel() }

    func cancel() {
        connection?.cancel()
        connection = nil
    }

    func probe() async -> ProbeResult {
        var setupMs: Int?
        var conn: NWConnection
        if let existing = connection, existing.state == .ready {
            conn = existing
        } else {
            cancel()
            let start = DispatchTime.now()
            switch await connect() {
            case .success(let c):
                conn = c
                connection = c
                setupMs = Self.ms(since: start)
            case .failure(let status):
                return ProbeResult(status: status)
            }
        }

        var result = await request(on: conn)
        // A kept-alive connection the server quietly closed isn't a signal failure:
        // reconnect once and retry so we measure the link, not the server's idle timeout.
        if result.status == .error, result.closedBeforeAnyBytes, setupMs == nil {
            cancel()
            let start = DispatchTime.now()
            switch await connect() {
            case .success(let c):
                conn = c
                connection = c
                setupMs = Self.ms(since: start)
                result = await request(on: conn)
            case .failure(let status):
                return ProbeResult(status: status)
            }
        }
        if result.status != .ok { cancel() }
        return ProbeResult(status: result.status, rttMs: result.rttMs, setupMs: setupMs)
    }

    // MARK: Connection

    private func connect() async -> Result<NWConnection, ProbeStatus> {
        let params = NWParameters(tls: NWProtocolTLS.Options(), tcp: {
            let tcp = NWProtocolTCP.Options()
            tcp.noDelay = true
            tcp.connectionTimeout = Int(timeout.rounded(.up))
            return tcp
        }())
        params.requiredInterfaceType = .cellular
        let conn = NWConnection(host: NWEndpoint.Host(host), port: 443, using: params)

        return await withCheckedContinuation { cont in
            let once = Once()
            let finish: (Result<NWConnection, ProbeStatus>) -> Void = { r in
                guard once.claim() else { return }
                if case .failure = r { conn.cancel() }
                conn.stateUpdateHandler = nil
                cont.resume(returning: r)
            }
            conn.stateUpdateHandler = { state in
                switch state {
                case .ready: finish(.success(conn))
                // .waiting = no usable (cellular) path right now.
                case .waiting: finish(.failure(.noPath))
                case .failed: finish(.failure(.error))
                case .cancelled: finish(.failure(.error))
                default: break
                }
            }
            conn.start(queue: queue)
            queue.asyncAfter(deadline: .now() + timeout) { finish(.failure(.timeout)) }
        }
    }

    // MARK: Request

    private struct RequestResult {
        var status: ProbeStatus
        var rttMs: Int?
        var closedBeforeAnyBytes = false
    }

    private func request(on conn: NWConnection) async -> RequestResult {
        let req = "GET \(path) HTTP/1.1\r\nHost: \(host)\r\nUser-Agent: RealSignalMap\r\nAccept: */*\r\nConnection: keep-alive\r\n\r\n"
        return await withCheckedContinuation { cont in
            let once = Once()
            let finish: (RequestResult) -> Void = { r in
                guard once.claim() else { return }
                cont.resume(returning: r)
            }
            let start = DispatchTime.now()
            var buffer = Data()

            func receive() {
                conn.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { data, _, isComplete, error in
                    if let data { buffer.append(data) }
                    switch HTTPResponseParser.parse(buffer) {
                    case .complete(let code):
                        finish(RequestResult(status: (200..<400).contains(code) ? .ok : .error,
                                             rttMs: Self.ms(since: start)))
                        return
                    case .invalid:
                        finish(RequestResult(status: .error))
                        return
                    case .incomplete:
                        break
                    }
                    if error != nil || isComplete {
                        finish(RequestResult(status: .error, closedBeforeAnyBytes: buffer.isEmpty))
                    } else {
                        receive()
                    }
                }
            }

            conn.send(content: Data(req.utf8), completion: .contentProcessed { error in
                if error != nil { finish(RequestResult(status: .error, closedBeforeAnyBytes: true)) }
            })
            receive()
            queue.asyncAfter(deadline: .now() + timeout) { finish(RequestResult(status: .timeout)) }
        }
    }

    private static func ms(since start: DispatchTime) -> Int {
        Int((DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000)
    }
}

/// Thread-safe one-shot flag for resuming a continuation exactly once.
private final class Once: @unchecked Sendable {
    private var done = false
    private let lock = NSLock()
    func claim() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if done { return false }
        done = true
        return true
    }
}

/// Minimal HTTP/1.1 response framing: enough to know when a response (headers + Content-Length body) is in.
enum HTTPResponseParser {
    enum Outcome: Equatable { case incomplete, complete(status: Int), invalid }

    static func parse(_ data: Data) -> Outcome {
        guard let headerEnd = data.range(of: Data("\r\n\r\n".utf8)) else {
            return data.count > 64 * 1024 ? .invalid : .incomplete
        }
        guard let head = String(data: data[data.startIndex..<headerEnd.lowerBound], encoding: .utf8) else { return .invalid }
        let lines = head.components(separatedBy: "\r\n")
        let statusParts = lines[0].split(separator: " ")
        guard statusParts.count >= 2, statusParts[0].hasPrefix("HTTP/"), let code = Int(statusParts[1]) else { return .invalid }

        var contentLength = 0
        var chunked = false
        for line in lines.dropFirst() {
            let kv = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            guard kv.count == 2 else { continue }
            if kv[0] == "content-length" { contentLength = Int(kv[1]) ?? 0 }
            if kv[0] == "transfer-encoding", kv[1].contains("chunked") { chunked = true }
        }
        // 204/304 never carry a body.
        if code == 204 || code == 304 || (100..<200).contains(code) { return .complete(status: code) }
        let bodyBytes = data.count - headerEnd.upperBound
        if chunked {
            // Done when the terminating zero-length chunk has arrived.
            return data[headerEnd.upperBound...].range(of: Data("0\r\n\r\n".utf8)) != nil ? .complete(status: code) : .incomplete
        }
        return bodyBytes >= contentLength ? .complete(status: code) : .incomplete
    }
}

/// Lets connect() report a failure status through `Result`.
extension ProbeStatus: Error {}
