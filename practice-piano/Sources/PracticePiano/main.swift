import AppKit
import AVFoundation
import PianoCore

// Exercise the real session with the supported keyboard commands, silently and
// in a temporary folder. Uses Apple sequencing to verify replay and cancellation.
if CommandLine.arguments.contains("--control-check") {
    do {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("PracticePiano-control-check-\(UUID().uuidString)")
        let session = try PianoSession(recordingsDirectory: directory)
        var failed = false
        var complete = false
        var recorded: URL?
        var starts = 0
        var stops = 0
        var playbackStarts = 0
        var playbackStops = 0
        var slider = -1
        session.onError = { text in fputs("Control check: \(text)\n", stderr); failed = true; complete = true }
        session.onRecordingChanged = { active in if active { starts += 1 } else { stops += 1 } }
        session.onKeyboardVolumeChanged = { slider = $0 }
        session.onRecordingSaved = { url in
            recorded = url
            session.receive(source: 2, bytes: Data([0x90, 0x5e, 127, 0x90, 0x5e, 0]), timestamp: 0)
        }
        session.onPlaybackChanged = { active in
            if active { playbackStarts += 1 }
            else {
                playbackStops += 1
                complete = true
            }
        }
        session.start(mutedForTesting: true)
        session.setInputRoles([1: .keystationKeyboard, 2: .transport])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            session.receive(source: 2, bytes: Data([0x90, 0x5f, 127, 0x90, 0x5f, 0]), timestamp: 0)
            session.receive(source: 1, bytes: Data([0xb0, 11, 64, 0x90, 60, 80]), timestamp: 0)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            session.receive(source: 1, bytes: Data([0x80, 60, 0]), timestamp: 0)
            session.receive(source: 2, bytes: Data([0x90, 0x5d, 127, 0x90, 0x5d, 0]), timestamp: 0)
        }
        let deadline = Date().addingTimeInterval(8)
        while !complete && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
        guard complete, !failed, starts == 1, stops == 1, playbackStarts == 1, playbackStops == 1, slider == 50,
              let recorded else { throw CocoaError(.fileReadCorruptFile) }
        let bytes = try Data(contentsOf: recorded)
        guard bytes.range(of: Data([0x90, 60, 80])) != nil,
              bytes.range(of: Data([0x90, 0x5f, 127])) == nil,
              bytes.range(of: Data([0x90, 0x5d, 127])) == nil,
              bytes.suffix(4) == Data([0, 0xff, 0x2f, 0]) else { throw CocoaError(.fileReadCorruptFile) }
        var shutDown = false
        // Auto-quit uses this same shutdown path while a take may still be open.
        session.onRecordingSaved = { _ in }
        session.startRecording { result in
            if case .failure = result { failed = true }
            session.receive(source: 1, bytes: Data([0x90, 64, 80]), timestamp: 0)
            session.shutdown { shutDown = true }
        }
        while !shutDown { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
        let takes = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        guard !failed, takes.count == 2, takes.allSatisfy({ $0.pathExtension == "mid" }),
              try takes.contains(where: { url in
                  let data = try Data(contentsOf: url)
                  return data.range(of: Data([0x90, 64, 80])) != nil && data.suffix(4) == Data([0, 0xff, 0x2f, 0])
              }) else { throw CocoaError(.fileReadCorruptFile) }
        try FileManager.default.removeItem(at: directory)
        print("Keystation controls, MIDI export, playback, and saving an active recording on shutdown verified.")
        exit(0)
    } catch { fputs("Control check failed: \(error)\n", stderr); exit(1) }
}

// Offline validation creates no window, opens no MIDI input, and makes no audible sound.
if CommandLine.arguments.contains("--audio-check") {
    do {
        let instrument = URL(fileURLWithPath: "/Library/Application Support/Logic/Sampler Instruments/01 Acoustic Pianos/Steinway Grand Piano 2.exs")
        let cache = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("PracticePiano-audio-check")
        let bank = try SteinwayBank.cachedBank(instrument: instrument, cacheDirectory: cache)
        let engine = AVAudioEngine()
        let sampler = AVAudioUnitSampler()
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
        engine.attach(sampler)
        engine.connect(sampler, to: engine.mainMixerNode, format: format)
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 512)
        try sampler.loadSoundBankInstrument(at: bank, program: 0, bankMSB: 0x79, bankLSB: 0)
        try engine.start()
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 512)!
        for note: UInt8 in [21, 48, 60, 84, 108] {
            for velocity: UInt8 in [20, 50, 75, 110] {
                sampler.startNote(note, withVelocity: velocity, onChannel: 0)
                var peak: Float = 0
                for _ in 0..<40 {
                    if try engine.renderOffline(512, to: buffer) == .success {
                        for i in 0..<Int(buffer.frameLength) { peak = max(peak, abs(buffer.floatChannelData![0][i])) }
                    }
                }
                guard peak > 0.00001 else { throw NSError(domain: "AudioCheck", code: 1, userInfo: [NSLocalizedDescriptionKey: "Silent note \(note), velocity \(velocity)"]) }
                print("note=\(note) velocity=\(velocity) peak=\(peak)")
                for message in MIDIState.silenceMessages { sampler.sendMIDIEvent(message.status, data1: message.data1, data2: message.data2) }
                // Render the release before measuring the next note in isolation.
                for _ in 0..<40 { _ = try engine.renderOffline(512, to: buffer) }
            }
        }
        func renderPeak() throws -> Float {
            var peak: Float = 0
            for _ in 0..<40 {
                if try engine.renderOffline(512, to: buffer) == .success {
                    for i in 0..<Int(buffer.frameLength) { peak = max(peak, abs(buffer.floatChannelData![0][i])) }
                }
            }
            return peak
        }
        for controller: UInt8 in [11, 7] {
            sampler.sendController(controller, withValue: 0, onChannel: 0)
            sampler.startNote(60, withVelocity: 75, onChannel: 0)
            let mutedPeak = try renderPeak()
            sampler.sendController(controller, withValue: 127, onChannel: 0)
            let audiblePeak = try renderPeak()
            guard mutedPeak < 0.00001, audiblePeak > 0.00001 else {
                throw NSError(domain: "AudioCheck", code: 4, userInfo: [NSLocalizedDescriptionKey: "Slider CC \(controller) did not change volume"])
            }
            sampler.stopNote(60, onChannel: 0)
            _ = try renderPeak()
            print("Slider CC \(controller): muted peak=\(mutedPeak), full peak=\(audiblePeak)")
        }
        var forceSustain = SustainOverride(enabled: true)
        for message in forceSustain.pedalMessages { sampler.sendMIDIEvent(message.status, data1: message.data1, data2: message.data2) }
        // A physical pedal-up message must not release a forced sustain.
        for message in forceSustain.process(MIDIMessage(0xb0, 64, 0)) { sampler.sendMIDIEvent(message.status, data1: message.data1, data2: message.data2) }
        sampler.startNote(60, withVelocity: 75, onChannel: 0)
        for _ in 0..<44 { _ = try engine.renderOffline(512, to: buffer) }
        sampler.stopNote(60, onChannel: 0)
        var sustainedPeak: Float = 0
        for pass in 0..<520 {
            if try engine.renderOffline(512, to: buffer) == .success && pass > 500 {
                for i in 0..<Int(buffer.frameLength) { sustainedPeak = max(sustainedPeak, abs(buffer.floatChannelData![0][i])) }
            }
        }
        guard sustainedPeak > 0.00001 else { throw NSError(domain: "AudioCheck", code: 2, userInfo: [NSLocalizedDescriptionKey: "Sustain became silent"]) }
        for message in forceSustain.setEnabled(false) { sampler.sendMIDIEvent(message.status, data1: message.data1, data2: message.data2) }
        for _ in 0..<100 { _ = try engine.renderOffline(512, to: buffer) }
        let releasedPeak = (0..<Int(buffer.frameLength)).map { abs(buffer.floatChannelData![0][$0]) }.max() ?? 0
        guard releasedPeak < 0.00001 else { throw NSError(domain: "AudioCheck", code: 3, userInfo: [NSLocalizedDescriptionKey: "Pedal release left a sounding note"]) }
        print("Forced sustain after six seconds peak=\(sustainedPeak); released peak=\(releasedPeak)")
        engine.stop()
        print("Steinway mono bank verified: \(bank.path)")
        exit(0)
    } catch { fputs("Audio check failed: \(error)\n", stderr); exit(1) }
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.run()
