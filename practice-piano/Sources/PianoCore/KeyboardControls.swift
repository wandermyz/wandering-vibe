import Foundation

public enum MIDIInputRole {
    case keyboard
    case keystationKeyboard
    case transport
}

public enum TransportCommand: Equatable {
    case record
    case play
    case stop
}

public enum KeyboardControl: Equatable {
    case volume(Int)
    case transport(TransportCommand)
}

public enum KeyboardControls {
    /// Transport decoding is restricted to the dedicated port: these note numbers
    /// are ordinary playable piano notes on the keyboard port.
    public static func decode(_ message: MIDIMessage, role: MIDIInputRole) -> KeyboardControl? {
        if role == .keystationKeyboard, message.kind == 0xb0,
           message.data1 == 7 || message.data1 == 11 {
            return .volume(Int((Double(message.data2) * 100 / 127).rounded()))
        }
        guard role == .transport, message.status == 0x90, message.data2 > 0 else { return nil }
        switch message.data1 {
        case 0x5d: return .transport(.stop)
        case 0x5e: return .transport(.play)
        case 0x5f: return .transport(.record)
        default: return nil
        }
    }
}

/// Retains the physical pedal state so disabling the override restores the pedal.
/// The effective pedal events are also written to the MIDI recording.
public struct SustainOverride {
    public private(set) var enabled: Bool
    private var physicalPedals: [UInt8: UInt8] = [:]

    public init(enabled: Bool = false) { self.enabled = enabled }

    public mutating func setEnabled(_ enabled: Bool) -> [MIDIMessage] {
        self.enabled = enabled
        return pedalMessages
    }

    public var pedalMessages: [MIDIMessage] {
        (UInt8(0)...15).map { MIDIMessage(0xb0 | $0, 64, enabled ? 127 : physicalPedals[$0] ?? 0) }
    }

    public mutating func process(_ message: MIDIMessage) -> [MIDIMessage] {
        guard message.kind == 0xb0 else { return [message] }
        if message.data1 == 64 {
            physicalPedals[message.channel] = message.data2
            return [MIDIMessage(message.status, 64, enabled ? 127 : message.data2)]
        }
        if message.data1 == 121 {
            physicalPedals.removeValue(forKey: message.channel)
            return enabled ? [message, MIDIMessage(message.status, 64, 127)] : [message]
        }
        return [message]
    }

    public mutating func resetPhysicalPedals() { physicalPedals.removeAll(keepingCapacity: true) }
}
