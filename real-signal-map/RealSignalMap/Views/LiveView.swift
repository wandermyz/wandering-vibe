import CoreLocation
import SwiftUI

struct LiveView: View {
    @EnvironmentObject private var recorder: Recorder
    @State private var overlay: SampleOverlay?

    var body: some View {
        ZStack {
            SignalMapView(overlay: overlay, mode: .follow)
                .ignoresSafeArea(edges: .top)

            VStack {
                statusPill
                Spacer()
                if recorder.authorization == .denied || recorder.authorization == .restricted {
                    locationDenied
                } else {
                    bottomCard
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 10)
        }
        .onChange(of: recorder.sessionCount) { _, _ in rebuild() }
        .onAppear(perform: rebuild)
    }

    private func rebuild() {
        overlay = SampleOverlay(.trace(Aggregation.segments(recorder.sessionSamples)))
    }

    private var statusPill: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(recorder.isRecording ? Color.red : Color.gray)
                .frame(width: 10, height: 10)
                .shadow(color: .red.opacity(recorder.isRecording ? 0.5 : 0), radius: 4)
            Text(recorder.isRecording ? "Recording" : "Paused").fontWeight(.semibold)
            if let s = recorder.lastSample, s.radio != .unknown {
                Text(s.radio.badge)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
            }
            Spacer()
            if let start = recorder.sessionStart {
                Text(start, style: .timer).monospacedDigit().foregroundStyle(.secondary)
            }
        }
        .font(.subheadline)
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .padding(.top, 4)
    }

    private var bottomCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 0) {
                    lastProbeCaption
                    lastProbeValue
                }
                Spacer()
                Sparkline(values: recorder.sessionSamples.suffix(40).map { $0.status.isFailure ? nil : $0.rttMs }, slots: 40)
                    .frame(width: 150, height: 56)
            }
            HStack {
                StatTile(value: "\(recorder.sessionCount)", label: "probes")
                StatTile(value: LatencyScale.format(ms: recorder.sessionMedian), label: "median")
                StatTile(value: "\(recorder.sessionFailures)", label: "failed",
                         color: recorder.sessionFailures > 0 ? Color(uiColor: LatencyScale.purple) : .primary)
                StatTile(value: distanceText, label: "distance")
            }
            LatencyLegend()
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 26))
    }

    @ViewBuilder private var lastProbeCaption: some View {
        if let s = recorder.lastSample {
            HStack(spacing: 4) {
                Text("LAST PROBE ·")
                Text(s.ts, style: .relative)
                Text("ago")
            }
            .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
        } else {
            Text(recorder.lastLocation == nil ? "WAITING FOR GPS…" : "PROBING…")
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var lastProbeValue: some View {
        if let s = recorder.lastSample {
            if let rtt = s.rttMs, !s.status.isFailure {
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text("\(rtt)").font(.system(size: 52, weight: .bold, design: .rounded)).monospacedDigit()
                    Text("ms").font(.title3.weight(.semibold)).foregroundStyle(.secondary)
                }
                .foregroundStyle(Color(latencyMs: rtt))
            } else {
                Text(failureText(s.status))
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(uiColor: LatencyScale.purple))
                    .padding(.vertical, 10)
            }
        } else {
            Text("—").font(.system(size: 52, weight: .bold, design: .rounded)).foregroundStyle(.tertiary)
        }
    }

    private func failureText(_ s: ProbeStatus) -> String {
        switch s {
        case .timeout: return "No internet"
        case .noPath: return "No cellular"
        default: return "Failed"
        }
    }

    private var distanceText: String {
        let m = recorder.sessionDistance
        return m >= 1000 ? String(format: "%.1f km", m / 1000) : "\(Int(m)) m"
    }

    private var locationDenied: some View {
        VStack(spacing: 10) {
            Text("Location access is off").font(.headline)
            Text("Real Signal Map needs your location to place each probe on the map.")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 26))
    }
}
