import AVFoundation
import PianoCore

/// All operations are serialized by PianoSession.queue, away from MIDI callbacks.
final class PianoEngine {
    private let engine = AVAudioEngine()
    private let sampler = AVAudioUnitSampler()
    private let queue: DispatchQueue
    private var idleWork: DispatchWorkItem?
    private var state = MIDIState()
    private var sequencer: AVAudioSequencer?
    private var playbackEnd: DispatchWorkItem?
    private var playbackControllerSnapshot: [MIDIMessage] = []
    var onPlaybackChanged: ((Bool) -> Void)?
    var isPlaying: Bool { sequencer?.isPlaying ?? false }
    private(set) var soundName = "Loading piano…"
    var onError: ((Error) -> Void)?
    var snapshot: [MIDIMessage] { state.snapshot }

    init(queue: DispatchQueue) {
        self.queue = queue
        engine.attach(sampler)
        connect()
        engine.mainMixerNode.outputVolume = 0.5
    }

    func loadPreferredInstrument() throws {
        let defaults = UserDefaults.standard
        if let path = defaults.string(forKey: "instrumentPath") {
            do { try load(URL(fileURLWithPath: path)); return }
            catch { onError?(error) }
        }
        let paths = [
            "/Library/Application Support/Logic/Sampler Instruments/01 Acoustic Pianos/Steinway Grand Piano 2.exs",
            "/Library/Application Support/Logic/Sampler Instruments/01 Acoustic Pianos/Steinway Piano 2.exs",
            "/Library/Application Support/GarageBand/Instrument Library/Sampler/Sampler Instruments/Steinway Grand Piano.exs"
        ]
        for path in paths where FileManager.default.fileExists(atPath: path) {
            let instrument = URL(fileURLWithPath: path)
            do { try load(instrument); return } catch { /* Try the compatibility bank. */ }
            do {
                let cache = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                    .appendingPathComponent("PracticePiano", isDirectory: true)
                let bank = try SteinwayBank.cachedBank(instrument: instrument, cacheDirectory: cache)
                try load(bank)
                soundName = "Steinway Grand Piano (mono)"
                return
            } catch { NSLog("Steinway compatibility: %@", error.localizedDescription) }
        }
        try load(URL(fileURLWithPath: "/System/Library/Components/CoreAudio.component/Contents/Resources/gs_instruments.dls"))
        soundName = "macOS Grand Piano (fallback)"
    }

    func load(_ url: URL) throws {
        silence()
        if ["sf2", "dls"].contains(url.pathExtension.lowercased()) {
            try sampler.loadSoundBankInstrument(at: url, program: 0, bankMSB: 0x79, bankLSB: 0)
        } else {
            try sampler.loadInstrument(at: url)
        }
        soundName = url.lastPathComponent == "gs_instruments.dls" ? "macOS Grand Piano" : url.deletingPathExtension().lastPathComponent
    }

    func send(_ message: MIDIMessage) throws {
        // Keyboard program/bank changes must not replace the selected piano.
        guard message.kind != 0xc0,
              !(message.kind == 0xb0 && (message.data1 == 0 || message.data1 == 32)) else { return }
        let startsNote = message.kind == 0x90 && message.data2 > 0
        if startsNote && !engine.isRunning { try engine.start() }
        state.apply(message)
        sampler.sendMIDIEvent(message.status, data1: message.data1, data2: message.data2)
        if state.isHoldingSound {
            idleWork?.cancel()
            idleWork = nil
        } else if engine.isRunning && !isPlaying {
            schedulePause()
        }
    }

    func silence() {
        idleWork?.cancel()
        idleWork = nil
        for message in MIDIState.silenceMessages {
            sampler.sendMIDIEvent(message.status, data1: message.data1, data2: message.data2)
        }
        state = MIDIState()
        engine.pause()
    }

    func setVolume(_ percentage: Int) { engine.mainMixerNode.outputVolume = Float(percentage) / 200 }

    func play(_ url: URL) throws {
        stopPlayback()
        let player = AVAudioSequencer(audioEngine: engine)
        try player.load(from: url, options: [])
        for track in player.tracks {
            track.destinationAudioUnit = sampler
            track.isLoopingEnabled = false
        }
        let duration = player.tracks.map(\.lengthInSeconds).max() ?? 0
        guard duration.isFinite, duration > 0 else { throw CocoaError(.fileReadCorruptFile) }
        playbackControllerSnapshot = state.snapshot.filter { $0.kind != 0x90 }
        silence()
        sequencer = player
        do {
            if !engine.isRunning { try engine.start() }
            player.currentPositionInSeconds = 0
            player.prepareToPlay()
            try player.start()
        } catch {
            stopPlayback()
            throw error
        }
        onPlaybackChanged?(true)
        let finish = DispatchWorkItem { [weak self] in self?.stopPlayback() }
        playbackEnd = finish
        queue.asyncAfter(deadline: .now() + duration + 0.1, execute: finish)
    }

    func stopPlayback() {
        playbackEnd?.cancel()
        playbackEnd = nil
        guard let player = sequencer else { return }
        let liveControllerChanges = state.snapshot.filter { $0.kind != 0x90 }
        player.stop()
        sequencer = nil
        silence()
        // Sequencer events bypass the live MIDI state. Restore the keyboard's
        // expression/pitch/pedal settings so replay cannot leave practice muted
        // or detuned. Slider changes made during replay take precedence.
        for channel: UInt8 in 0...15 { sampler.sendMIDIEvent(0xb0 | channel, data1: 121, data2: 0) }
        for message in playbackControllerSnapshot + liveControllerChanges { try? send(message) }
        playbackControllerSnapshot.removeAll(keepingCapacity: false)
        onPlaybackChanged?(false)
    }

    func resetAudioRoute() {
        stopPlayback()
        silence()
        engine.stop()
        connect()
    }

    func shutdown() { stopPlayback(); silence(); engine.stop() }

    private func connect() {
        // An explicit sampler format also works when the output device runs at 48 kHz.
        engine.connect(sampler, to: engine.mainMixerNode,
                       format: AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2))
    }

    private func schedulePause() {
        idleWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.state.isHoldingSound else { return }
            self.engine.pause()
            self.idleWork = nil
        }
        idleWork = work
        queue.asyncAfter(deadline: .now() + 15, execute: work)
    }
}
