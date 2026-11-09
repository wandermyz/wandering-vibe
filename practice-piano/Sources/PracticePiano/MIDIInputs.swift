import CoreMIDI
import Foundation
import PianoCore

struct MIDIInput {
    let endpoint: MIDIEndpointRef
    let id: MIDIUniqueID
    let name: String
    let device: MIDIDeviceRef
    let role: MIDIInputRole
}

final class MIDIInputs {
    private var client: MIDIClientRef = 0
    private var port: MIDIPortRef = 0
    private var connected = Set<MIDIEndpointRef>()
    private(set) var sources: [MIDIInput] = []
    private let session: PianoSession
    var onChanged: (() -> Void)?
    var selectedID: MIDIUniqueID? {
        didSet {
            UserDefaults.standard.set(selectedID.map { Int($0) }, forKey: "midiSourceID")
            disconnect()
            refresh()
        }
    }

    init(session: PianoSession) throws {
        self.session = session
        selectedID = (UserDefaults.standard.object(forKey: "midiSourceID") as? Int).map { MIDIUniqueID($0) }
        try check(MIDIClientCreateWithBlock("PracticePiano" as CFString, &client) { [weak self] _ in
            DispatchQueue.main.async { self?.refresh() }
        })
        do {
            try check(MIDIInputPortCreateWithBlock(client, "Keyboard Input" as CFString, &port) { [weak session] list, context in
                let source = UInt32(UInt(bitPattern: context))
                var packet = UnsafeRawPointer(list).advanced(by: MemoryLayout<MIDIPacketList>.offset(of: \.packet)!).assumingMemoryBound(to: MIDIPacket.self)
                for _ in 0..<list.pointee.numPackets {
                    let dataPointer = UnsafeRawPointer(packet).advanced(by: MemoryLayout<MIDIPacket>.offset(of: \.data)!)
                    let bytes = Data(bytes: dataPointer, count: Int(packet.pointee.length))
                    session?.receive(source: source, bytes: bytes, timestamp: packet.pointee.timeStamp)
                    packet = UnsafePointer(MIDIPacketNext(packet))
                }
            })
        } catch { MIDIClientDispose(client); client = 0; throw error }
        refresh()
    }

    deinit { shutdown() }

    func refresh() {
        guard client != 0 else { return }
        sources = (0..<MIDIGetNumberOfSources()).compactMap { index in
            let source = MIDIGetSource(index)
            guard source != 0 else { return nil }
            var offline: Int32 = 0
            MIDIObjectGetIntegerProperty(source, kMIDIPropertyOffline, &offline)
            guard offline == 0 else { return nil }
            var id: Int32 = 0
            MIDIObjectGetIntegerProperty(source, kMIDIPropertyUniqueID, &id)
            var name: Unmanaged<CFString>?
            MIDIObjectGetStringProperty(source, kMIDIPropertyDisplayName, &name)
            let displayName = name?.takeRetainedValue() as String? ?? "MIDI Keyboard"
            let lowerName = displayName.lowercased()
            let role: MIDIInputRole
            if lowerName.contains("keystation") && lowerName.contains("transport") { role = .transport }
            else if lowerName.contains("keystation") { role = .keystationKeyboard }
            else { role = .keyboard }
            var entity: MIDIEntityRef = 0
            var device: MIDIDeviceRef = 0
            MIDIEndpointGetEntity(source, &entity)
            MIDIEntityGetDevice(entity, &device)
            return MIDIInput(endpoint: source, id: id, name: displayName, device: device, role: role)
        }
        // The earlier menu exposed the transport endpoint as a selectable input.
        // Migrate that saved choice to its keyboard endpoint, preserving the device.
        if let selected = sources.first(where: { $0.id == selectedID && $0.role == .transport }),
           let keyboard = sources.first(where: { $0.role == .keystationKeyboard && $0.device == selected.device }) {
            selectedID = keyboard.id
            return
        }
        session.setInputRoles(Dictionary(uniqueKeysWithValues: sources.map { ($0.endpoint, $0.role) }))
        let selectedDevice = sources.first { $0.id == selectedID }?.device
        let desired = Set(sources.filter {
            selectedID == nil || $0.id == selectedID
                || ($0.role == .transport && $0.device != 0 && $0.device == selectedDevice)
        }.map(\.endpoint))
        let removed = connected.subtracting(desired)
        for source in removed { MIDIPortDisconnectSource(port, source); connected.remove(source) }
        if !removed.isEmpty { session.resetInputs() }
        for source in desired.subtracting(connected) {
            let result = MIDIPortConnectSource(port, source, UnsafeMutableRawPointer(bitPattern: UInt(source)))
            if result == noErr { connected.insert(source) }
            else { session.onError?("Could not connect MIDI input (\(result)).") }
        }
        onChanged?()
    }

    var status: String {
        let names = sources.filter { connected.contains($0.endpoint) && $0.role != .transport }.map(\.name)
        if names.isEmpty { return selectedID == nil ? "No MIDI keyboard connected" : "Selected MIDI keyboard is disconnected" }
        return names.joined(separator: ", ")
    }

    var hasKeyboard: Bool {
        // Virtual app endpoints have no hardware device; a transport endpoint
        // alone cannot provide piano input. Sources are already filtered online.
        sources.contains { $0.device != 0 && $0.role != .transport }
    }

    func shutdown() {
        guard client != 0 else { return }
        disconnect()
        MIDIPortDispose(port)
        MIDIClientDispose(client)
        port = 0
        client = 0
    }

    private func disconnect() {
        for source in connected { MIDIPortDisconnectSource(port, source) }
        connected.removeAll()
        session.resetInputs()
    }

    private func check(_ status: OSStatus) throws {
        guard status == noErr else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
    }
}
