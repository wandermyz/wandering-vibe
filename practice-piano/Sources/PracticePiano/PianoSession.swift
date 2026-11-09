import AVFoundation
import PianoCore

final class PianoSession {
    let queue = DispatchQueue(label: "PracticePiano.midi", qos: .userInteractive)
    private var piano: PianoEngine?
    private var parsers: [UInt32: MIDIParser] = [:]
    private var inputRoles: [UInt32: MIDIInputRole] = [:]
    private var recorder: MIDIRecorder?
    private var recordingError: Error?
    private var audioErrorReported = false
    private var configurationObserver: NSObjectProtocol?
    private var sustain = SustainOverride(enabled: UserDefaults.standard.bool(forKey: "forceSustain"))
    private var transportEnabled = true
    private var latestRecording: URL?
    private var keyboardVolumeWork: DispatchWorkItem?
    private var keyboardVolume = 100
    let recordingsDirectory: URL
    var onError: ((String) -> Void)?
    var onSoundChanged: ((String) -> Void)?
    var onRecordingChanged: ((Bool) -> Void)?
    var onRecordingSaved: ((URL) -> Void)?
    var onPlaybackChanged: ((Bool) -> Void)?
    var onKeyboardVolumeChanged: ((Int) -> Void)?

    init(recordingsDirectory: URL? = nil) throws {
        if let recordingsDirectory { self.recordingsDirectory = recordingsDirectory }
        else {
            self.recordingsDirectory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent("PracticePiano/Recordings", isDirectory: true)
        }
        try FileManager.default.createDirectory(at: self.recordingsDirectory, withIntermediateDirectories: true)
        latestRecording = try FileManager.default.contentsOfDirectory(at: self.recordingsDirectory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "mid" }.sorted { $0.lastPathComponent > $1.lastPathComponent }.first
    }

    func start(mutedForTesting: Bool = false) {
        queue.async { [self] in
            let sound = PianoEngine(queue: queue)
            piano = sound
            sound.onError = { [weak self] error in self?.report(error.localizedDescription) }
            sound.onPlaybackChanged = { [weak self] playing in
                guard let self else { return }
                if !playing { self.restoreSustain() }
                self.notify { $0.onPlaybackChanged?(playing) }
            }
            do {
                try sound.loadPreferredInstrument()
                sound.setVolume(mutedForTesting ? 0 : UserDefaults.standard.object(forKey: "volume") as? Int ?? 80)
                restoreSustain()
                updateSound(sound.soundName)
            } catch { report("Could not load a piano: \(error.localizedDescription)"); updateSound("Piano unavailable — choose an instrument") }
        }
        configurationObserver = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: nil, queue: nil) { [weak self] _ in
            self?.resetAudio()
        }
    }

    func setInputRoles(_ roles: [UInt32: MIDIInputRole]) { queue.async { [self] in inputRoles = roles } }
    func setTransportEnabled(_ enabled: Bool) { queue.async { [self] in transportEnabled = enabled } }
    func setLatestRecording(_ url: URL) { queue.async { [self] in latestRecording = url } }

    func receive(source: UInt32, bytes: Data, timestamp: UInt64) {
        let time = AVAudioTime.seconds(forHostTime: timestamp == 0 ? mach_absolute_time() : timestamp)
        queue.async { [weak self] in
            guard let self else { return }
            autoreleasepool {
                let role = self.inputRoles[source] ?? .keyboard
                var parser = self.parsers[source] ?? MIDIParser()
                parser.consume(bytes) { message in
                    if let control = KeyboardControls.decode(message, role: role) {
                        switch control {
                        case .transport(let command):
                            if self.transportEnabled { self.handleTransport(command, time: time) }
                        case .volume(let percentage): self.updateKeyboardVolume(percentage)
                        }
                    }
                    // Dedicated transport port messages are never piano notes or recording data.
                    if role != .transport { self.handle(message, time: time) }
                }
                self.parsers[source] = parser
            }
        }
    }

    private func handle(_ message: MIDIMessage, time: Double) {
        if message.kind == 0x90 && message.data2 > 0 { piano?.stopPlayback() }
        for effective in sustain.process(message) { handleEffective(effective, time: time) }
    }

    private func handleEffective(_ message: MIDIMessage, time: Double) {
        do {
            try piano?.send(message)
            audioErrorReported = false
        } catch {
            if !audioErrorReported { report("Audio could not start: \(error.localizedDescription)"); audioErrorReported = true }
        }
        if let recorder, recordingError == nil {
            do { try recorder.record(message, time: time) }
            catch { recordingError = error; report("Recording write failed. Stop recording to recover the draft. \(error.localizedDescription)") }
        }
    }

    private func handleTransport(_ command: TransportCommand, time: Double) {
        do {
            switch command {
            case .record: try startRecordingOnQueue(time: time)
            case .stop:
                piano?.stopPlayback()
                _ = try stopRecordingOnQueue(time: time)
                silenceOnQueue()
            case .play:
                _ = try stopRecordingOnQueue(time: time)
                try playLatestOnQueue()
            }
        } catch { report("Keyboard transport: \(error.localizedDescription)") }
    }

    private func startRecordingOnQueue(time: Double) throws {
        guard recorder == nil else { return }
        piano?.stopPlayback()
        let date = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let url = recordingsDirectory.appendingPathComponent("Practice-\(date)-\(UUID().uuidString.prefix(4)).mid.draft")
        recorder = try MIDIRecorder(url: url, startTime: time, snapshot: piano?.snapshot ?? [])
        recordingError = nil
        notify { $0.onRecordingChanged?(true) }
    }

    private func stopRecordingOnQueue(time: Double) throws -> URL? {
        guard let active = recorder else { return nil }
        defer {
            recorder = nil
            recordingError = nil
            notify { $0.onRecordingChanged?(false) }
        }
        if let error = recordingError { throw error }
        try active.finish(time: time)
        let completed = active.url.deletingPathExtension()
        try FileManager.default.moveItem(at: active.url, to: completed)
        latestRecording = completed
        notify { $0.onRecordingSaved?(completed) }
        return completed
    }

    func startRecording(completion: @escaping (Result<Void, Error>) -> Void) {
        queue.async { [self] in
            do { try startRecordingOnQueue(time: now()); DispatchQueue.main.async { completion(.success(())) } }
            catch { DispatchQueue.main.async { completion(.failure(error)) } }
        }
    }

    func stopRecording(completion: @escaping (Result<URL?, Error>) -> Void) {
        queue.async { [self] in
            do { let url = try stopRecordingOnQueue(time: now()); DispatchQueue.main.async { completion(.success(url)) } }
            catch { DispatchQueue.main.async { completion(.failure(error)) } }
        }
    }

    func playLatest() {
        queue.async { [self] in
            do { _ = try stopRecordingOnQueue(time: now()); try playLatestOnQueue() }
            catch { report("Could not play recording: \(error.localizedDescription)") }
        }
    }

    private func playLatestOnQueue() throws {
        guard let latestRecording else { report("Record a take before pressing Play."); return }
        try piano?.play(latestRecording)
    }

    func stop() { queue.async { [self] in handleTransport(.stop, time: now()) } }

    func setForceSustain(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: "forceSustain")
        queue.async { [self] in
            piano?.stopPlayback()
            for message in sustain.setEnabled(enabled) { handleEffective(message, time: now()) }
        }
    }

    func resetInputs() {
        queue.async { [self] in
            silenceOnQueue()
            sustain.resetPhysicalPedals()
            restoreSustain()
            parsers.removeAll(keepingCapacity: true)
        }
    }

    func panic() {
        queue.async { [self] in
            piano?.stopPlayback()
            silenceOnQueue()
        }
    }

    private func silenceOnQueue() {
        for message in MIDIState.silenceMessages { handleEffective(message, time: now()) }
        piano?.silence()
        restoreSustain()
    }

    private func restoreSustain() {
        for message in sustain.pedalMessages { handleEffective(message, time: now()) }
    }

    func resetAudio() {
        queue.async { [self] in
            silenceOnQueue()
            piano?.resetAudioRoute()
            restoreSustain()
        }
    }

    func setVolume(_ percentage: Int) {
        UserDefaults.standard.set(percentage, forKey: "volume")
        queue.async { [self] in piano?.setVolume(percentage) }
    }

    private func updateKeyboardVolume(_ percentage: Int) {
        keyboardVolume = percentage
        // A fast slider sweep can send hundreds of CCs. Only menu updates are coalesced;
        // every actual MIDI controller event still reaches the sampler and recording.
        guard keyboardVolumeWork == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.keyboardVolumeWork = nil
            let value = self.keyboardVolume
            self.notify { $0.onKeyboardVolumeChanged?(value) }
        }
        keyboardVolumeWork = work
        queue.asyncAfter(deadline: .now() + 0.1, execute: work)
    }

    func setInstrument(_ url: URL?) {
        queue.async { [self] in
            piano?.stopPlayback()
            silenceOnQueue()
            UserDefaults.standard.set(url?.path, forKey: "instrumentPath")
            do {
                if let url { try piano?.load(url) } else { try piano?.loadPreferredInstrument() }
                restoreSustain()
                updateSound(piano?.soundName ?? "Piano unavailable")
            } catch {
                report("Could not load the instrument: \(error.localizedDescription)")
                UserDefaults.standard.removeObject(forKey: "instrumentPath")
                do { try piano?.loadPreferredInstrument(); restoreSustain(); updateSound(piano?.soundName ?? "Piano unavailable") }
                catch { report(error.localizedDescription) }
            }
        }
    }

    func testSound() {
        queue.async { [self] in
            piano?.stopPlayback()
            handle(MIDIMessage(0x90, 60, 80), time: now())
            queue.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                guard let self else { return }
                self.handle(MIDIMessage(0x80, 60, 0), time: self.now())
            }
        }
    }

    func shutdown(completion: @escaping () -> Void) {
        if let observer = configurationObserver { NotificationCenter.default.removeObserver(observer) }
        stopRecording { [self] result in
            if case .failure(let error) = result { report("Draft preserved in Recordings: \(error.localizedDescription)") }
            queue.async { [self] in
                keyboardVolumeWork?.cancel()
                piano?.shutdown()
                DispatchQueue.main.async(execute: completion)
            }
        }
    }

    private func now() -> Double { AVAudioTime.seconds(forHostTime: mach_absolute_time()) }
    private func notify(_ action: @escaping (PianoSession) -> Void) { DispatchQueue.main.async { [weak self] in if let self { action(self) } } }
    private func report(_ text: String) { notify { $0.onError?(text) } }
    private func updateSound(_ text: String) { notify { $0.onSoundChanged?(text) } }
}
