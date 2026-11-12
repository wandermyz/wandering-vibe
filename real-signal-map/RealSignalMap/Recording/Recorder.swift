import CoreLocation
import SwiftUI

/// Runs whenever the app is in the foreground: tracks location, probes over cellular
/// every `settings.interval` seconds or `settings.distance` metres (read live), and stores samples.
@MainActor
final class Recorder: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var isRecording = false
    @Published private(set) var authorization: CLAuthorizationStatus = .notDetermined
    @Published private(set) var lastSample: Sample?
    @Published private(set) var lastLocation: CLLocation?
    /// Samples of the current session (newest last), capped for the live trace.
    @Published private(set) var sessionSamples: [Sample] = []
    @Published private(set) var sessionStart: Date?
    @Published private(set) var sessionCount = 0
    @Published private(set) var sessionFailures = 0
    @Published private(set) var sessionDistance: Double = 0

    static let liveTraceLimit = 6_000
    /// Serial so batches land in order.
    private static let writeQueue = DispatchQueue(label: "Recorder.write", qos: .utility)

    private let settings: AppSettings
    private let store: SampleStore
    private let radio = RadioInfo()
    private let manager = CLLocationManager()
    private var prober: Prober?
    private var timer: Timer?
    private var inFlight = false
    private var lastProbeAt: Date?
    private var lastProbeLocation: CLLocation?
    private var lastDistanceLocation: CLLocation?
    private var sessionId: Int64 = 0
    private var sortedRtts: [Int] = []
    private var pending: [Sample] = []
    private var lastFlush = Date()

    init(settings: AppSettings, store: SampleStore) {
        self.settings = settings
        self.store = store
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.activityType = .automotiveNavigation
        manager.distanceFilter = kCLDistanceFilterNone
        manager.pausesLocationUpdatesAutomatically = false
        authorization = manager.authorizationStatus
    }

    var sessionMedian: Int? {
        sortedRtts.isEmpty ? nil : sortedRtts[sortedRtts.count / 2]
    }

    // MARK: Lifecycle

    func start() {
        guard !isRecording else { return }
        isRecording = true
        UIApplication.shared.isIdleTimerDisabled = true
        sessionId = Int64(Date().timeIntervalSince1970 * 1000)
        sessionStart = Date()
        sessionSamples = []
        sessionCount = 0
        sessionFailures = 0
        sessionDistance = 0
        sortedRtts = []
        lastProbeAt = nil
        lastProbeLocation = nil
        lastDistanceLocation = nil

        let target = settings.probeTarget
        if prober?.host != target.host || prober?.path != target.path || prober?.timeout != settings.timeout {
            prober?.cancel()
            prober = Prober(host: target.host, path: target.path, timeout: settings.timeout)
        }

        if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() }
        manager.startUpdatingLocation()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    func stop() {
        guard isRecording else { return }
        isRecording = false
        UIApplication.shared.isIdleTimerDisabled = false
        timer?.invalidate()
        timer = nil
        manager.stopUpdatingLocation()
        prober?.cancel()
        flush()
    }

    // MARK: Probing

    private func tick() {
        guard isRecording, !inFlight, let prober, let loc = lastLocation else { return }
        // Only record with a fresh, reasonably accurate fix.
        guard loc.horizontalAccuracy >= 0, loc.horizontalAccuracy <= AppSettings.maxHorizontalAccuracy,
              -loc.timestamp.timeIntervalSinceNow < 10 else { return }

        let now = Date()
        let dueByTime = lastProbeAt.map { now.timeIntervalSince($0) >= settings.interval } ?? true
        let dueByDistance = lastProbeLocation.map { loc.distance(from: $0) >= settings.distance } ?? true
        guard dueByTime || dueByDistance else { return }

        inFlight = true
        lastProbeAt = now
        lastProbeLocation = loc
        let radioNow = radio.current
        let session = sessionId
        Task {
            let r = await prober.probe()
            let sample = Sample(ts: now, lat: loc.coordinate.latitude, lon: loc.coordinate.longitude,
                                hAcc: loc.horizontalAccuracy, speed: max(0, loc.speed),
                                rttMs: r.rttMs, setupMs: r.setupMs, status: r.status,
                                radio: radioNow, session: session)
            self.record(sample)
            self.inFlight = false
        }
    }

    private func record(_ s: Sample) {
        // Drop results from a session that has since ended (app went to background mid-probe).
        guard isRecording, s.session == sessionId else { return }
        lastSample = s
        sessionCount += 1
        if s.status.isFailure { sessionFailures += 1 }
        if let rtt = s.rttMs {
            let idx = sortedRtts.firstIndex(where: { $0 >= rtt }) ?? sortedRtts.count
            sortedRtts.insert(rtt, at: idx)
        }
        sessionSamples.append(s)
        if sessionSamples.count > Self.liveTraceLimit { sessionSamples.removeFirst(sessionSamples.count - Self.liveTraceLimit) }
        pending.append(s)
        if pending.count >= 10 || Date().timeIntervalSince(lastFlush) > 30 { flush() }
    }

    func flush() {
        let batch = pending
        pending = []
        lastFlush = Date()
        let cap = settings.maxPoints
        let store = store
        Self.writeQueue.async { store.insert(batch, cap: cap) }
    }

    // MARK: CLLocationManagerDelegate

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            for loc in locations { self.accept(loc) }
            self.tick()
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in self.authorization = status }
    }

    private func accept(_ loc: CLLocation) {
        lastLocation = loc
        guard loc.horizontalAccuracy >= 0, loc.horizontalAccuracy <= 30 else { return }
        if let prev = lastDistanceLocation {
            let d = loc.distance(from: prev)
            // Ignore GPS jitter while stationary.
            if d >= max(5, loc.horizontalAccuracy) {
                sessionDistance += d
                lastDistanceLocation = loc
            }
        } else {
            lastDistanceLocation = loc
        }
    }
}
