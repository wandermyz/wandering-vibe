import AVFoundation
import Combine
import Foundation

@MainActor
final class AudioRecorder: NSObject, ObservableObject {
    enum State: Equatable {
        case idle
        case recording
        case stopped
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var level: Float = 0  // 0...1, smoothed

    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private(set) var startedAt: Date?
    private(set) var fileURL: URL?

    // Peak samples captured ~10 Hz for in-memory waveform of the current take.
    private(set) var samples: [Float] = []

    func start() throws {
        guard state != .recording else { return }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.allowBluetoothHFP, .defaultToSpeaker])
        try session.setActive(true, options: [])

        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("recordings", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("\(UUID().uuidString).m4a")

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]

        let r = try AVAudioRecorder(url: url, settings: settings)
        r.delegate = self
        r.isMeteringEnabled = true
        guard r.record() else {
            throw NSError(domain: "AudioRecorder", code: 1, userInfo: [NSLocalizedDescriptionKey: "record() returned false"])
        }

        recorder = r
        fileURL = url
        startedAt = Date()
        samples = []
        elapsed = 0
        level = 0
        state = .recording

        let t = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        guard let recorder, state == .recording else { return }
        recorder.stop()
        timer?.invalidate()
        timer = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        state = .stopped
    }

    private func tick() {
        guard let recorder, recorder.isRecording else { return }
        recorder.updateMeters()
        let db = recorder.averagePower(forChannel: 0)
        // -60 dB silence floor → 0; 0 dB peak → 1
        let norm = max(0, min(1, (db + 60) / 60))
        level = level * 0.6 + norm * 0.4  // simple smoothing
        samples.append(norm)
        elapsed = recorder.currentTime
    }

    func reset() {
        recorder = nil
        fileURL = nil
        startedAt = nil
        samples = []
        elapsed = 0
        level = 0
        state = .idle
    }
}

extension AudioRecorder: AVAudioRecorderDelegate {
    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        Task { @MainActor in
            self.state = .failed(error?.localizedDescription ?? "encode error")
        }
    }
}
