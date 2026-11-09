import Foundation

/// Standard MIDI format 0, 480 PPQ, 120 BPM. Memory is bounded to a 4 KB buffer.
/// Call only from the app's serial MIDI queue.
public final class MIDIRecorder {
    public let url: URL
    private let file: FileHandle
    private let startTime: Double
    private var lastTick: UInt64 = 0
    private var trackSize: UInt64 = 0
    private var buffer = Data()
    private var finished = false

    public init(url: URL, startTime: Double, snapshot: [MIDIMessage] = []) throws {
        self.url = url
        self.startTime = startTime
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        file = try FileHandle(forUpdating: url)
        // Header, single track, 480 ticks/quarter; track length is patched on finish.
        try file.write(contentsOf: Data([
            0x4d, 0x54, 0x68, 0x64, 0, 0, 0, 6, 0, 0, 0, 1, 1, 0xe0,
            0x4d, 0x54, 0x72, 0x6b, 0, 0, 0, 0
        ]))
        append([0, 0xff, 0x51, 3, 7, 0xa1, 0x20]) // 500,000 µs/quarter.
        for channel: UInt8 in 0...15 { append([0, 0xc0 | channel, 0]) }
        for message in snapshot { try record(message, time: startTime) }
    }

    deinit { try? file.close() }

    public func record(_ message: MIDIMessage, time: Double) throws {
        guard !finished else { return }
        try advance(to: time)
        append(message.bytes)
        if buffer.count >= 4096 { try flush() }
    }

    public func finish(time: Double) throws {
        guard !finished else { return }
        for message in MIDIState.silenceMessages { try record(message, time: time) }
        append([0, 0xff, 0x2f, 0])
        try flush()
        guard trackSize <= UInt64(UInt32.max) else { throw CocoaError(.fileWriteOutOfSpace) }
        try file.seek(toOffset: 18)
        let size = UInt32(trackSize)
        try file.write(contentsOf: Data([UInt8(size >> 24), UInt8(truncatingIfNeeded: size >> 16),
                                        UInt8(truncatingIfNeeded: size >> 8), UInt8(truncatingIfNeeded: size)]))
        try file.synchronize()
        try file.close()
        finished = true
    }

    private func advance(to time: Double) throws {
        let elapsed = max(0, time - startTime)
        guard elapsed.isFinite, elapsed < Double(UInt64.max / 960) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let tick = max(lastTick, UInt64((elapsed * 960).rounded()))
        var delta = tick - lastTick
        // SMF delta times are limited to four bytes; bridge very long silences.
        while delta > 0x0fffffff {
            append(Self.variableLength(0x0fffffff) + [0xff, 0x01, 0])
            delta -= 0x0fffffff
        }
        append(Self.variableLength(UInt32(delta)))
        lastTick = tick
    }

    private func append(_ bytes: [UInt8]) {
        buffer.append(contentsOf: bytes)
        trackSize += UInt64(bytes.count)
    }

    private func flush() throws {
        try file.write(contentsOf: buffer)
        buffer.removeAll(keepingCapacity: true)
    }

    public static func variableLength(_ value: UInt32) -> [UInt8] {
        precondition(value <= 0x0fffffff)
        var remainder = value
        var bytes = [UInt8(remainder & 0x7f)]
        remainder >>= 7
        while remainder > 0 {
            bytes.insert(UInt8(remainder & 0x7f) | 0x80, at: 0)
            remainder >>= 7
        }
        return bytes
    }
}
