import Foundation

public struct MIDIMessage: Equatable {
    public let status: UInt8
    public let data1: UInt8
    public let data2: UInt8
    public var channel: UInt8 { status & 0x0f }
    public var kind: UInt8 { status & 0xf0 }
    public var bytes: [UInt8] {
        kind == 0xc0 || kind == 0xd0 ? [status, data1] : [status, data1, data2]
    }

    public init(_ status: UInt8, _ data1: UInt8, _ data2: UInt8 = 0) {
        self.status = status
        self.data1 = data1
        self.data2 = data2
    }
}

/// One parser per MIDI source: running status and partial messages span packets.
public struct MIDIParser {
    private var status: UInt8 = 0
    private var firstData: UInt8?
    private var systemBytesRemaining = 0
    private var inSysEx = false

    public init() {}

    public mutating func consume(_ bytes: Data, emit: (MIDIMessage) -> Void) {
        for byte in bytes {
            if byte >= 0xf8 { continue } // Clock/active sensing may interrupt any message.
            if byte >= 0x80 {
                firstData = nil
                if byte >= 0xf0 {
                    status = 0
                    inSysEx = byte == 0xf0
                    switch byte {
                    case 0xf1, 0xf3: systemBytesRemaining = 1
                    case 0xf2: systemBytesRemaining = 2
                    default: systemBytesRemaining = 0
                    }
                } else {
                    inSysEx = false
                    systemBytesRemaining = 0
                    status = byte
                }
                continue
            }
            if inSysEx { continue }
            if systemBytesRemaining > 0 {
                systemBytesRemaining -= 1
                continue
            }
            guard status != 0 else { continue }
            if status & 0xe0 == 0xc0 {
                emit(MIDIMessage(status, byte))
            } else if let first = firstData {
                emit(MIDIMessage(status, first, byte))
                firstData = nil
            } else {
                firstData = byte
            }
        }
    }
}

public struct MIDIState {
    public private(set) var notes: [UInt16: UInt8] = [:]
    private var controls: [UInt16: UInt8] = [:]
    private var bends: [UInt8: MIDIMessage] = [:]
    public var isHoldingSound: Bool {
        !notes.isEmpty || controls.contains { entry in
            let controller = entry.key & 0x7f
            return (controller == 64 || controller == 66) && entry.value >= 64
        }
    }
    public init() {}

    public mutating func apply(_ message: MIDIMessage) {
        let key = UInt16(message.channel) * 128 + UInt16(message.data1)
        switch message.kind {
        case 0x90 where message.data2 > 0: notes[key] = message.data2
        case 0x80, 0x90: notes.removeValue(forKey: key)
        case 0xb0:
            if message.data1 == 120 || message.data1 == 123 {
                notes = notes.filter { $0.key / 128 != UInt16(message.channel) }
            } else if message.data1 == 121 {
                controls = controls.filter { $0.key / 128 != UInt16(message.channel) }
                bends.removeValue(forKey: message.channel)
            } else { controls[key] = message.data2 }
        case 0xe0: bends[message.channel] = message
        default: break
        }
    }

    public var snapshot: [MIDIMessage] {
        controls.keys.sorted().map { MIDIMessage(0xb0 | UInt8($0 / 128), UInt8($0 % 128), controls[$0]!) }
        + bends.keys.sorted().map { bends[$0]! }
        + notes.keys.sorted().map { MIDIMessage(0x90 | UInt8($0 / 128), UInt8($0 % 128), notes[$0]!) }
    }

    public static var silenceMessages: [MIDIMessage] {
        (UInt8(0)...15).flatMap { channel in
            [MIDIMessage(0xb0 | channel, 64, 0), MIDIMessage(0xb0 | channel, 66, 0),
             MIDIMessage(0xb0 | channel, 120, 0), MIDIMessage(0xb0 | channel, 123, 0)]
        }
    }
}
