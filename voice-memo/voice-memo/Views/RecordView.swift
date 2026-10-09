import AVFoundation
import SwiftUI

struct RecordView: View {
    @EnvironmentObject private var recordings: LocalRecordingsStore
    @StateObject private var recorder = AudioRecorder()
    @State private var locationProvider = LocationProvider()

    @State private var locationName: String?
    @State private var status: Status = .idle
    @State private var lastSavedFilename: String?

    enum Status: Equatable { case idle, recording, saved, failed(String) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                Text(formatted(recorder.elapsed))
                    .font(.system(size: 56, weight: .light, design: .monospaced))
                    .foregroundStyle(recorder.state == .recording ? .red : .primary)

                WaveformView(samples: recorder.samples)
                    .frame(height: 80)
                    .padding(.horizontal)

                if let locationName, recorder.state == .recording {
                    Label(locationName, systemImage: "location.fill")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                recordButton

                statusFooter
                    .frame(minHeight: 44)
                    .padding(.horizontal)
            }
            .padding(.bottom, 24)
            .navigationTitle("Record")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var recordButton: some View {
        Button {
            Task { await toggle() }
        } label: {
            ZStack {
                Circle().fill(.red.opacity(0.15)).frame(width: 96, height: 96)
                if recorder.state == .recording {
                    RoundedRectangle(cornerRadius: 6).fill(.red).frame(width: 36, height: 36)
                } else {
                    Circle().fill(.red).frame(width: 72, height: 72)
                }
            }
        }
    }

    @ViewBuilder
    private var statusFooter: some View {
        switch status {
        case .idle:
            Color.clear
        case .recording:
            Color.clear
        case .saved:
            Label("Saved \(lastSavedFilename ?? "")", systemImage: "checkmark.circle.fill")
                .font(.footnote)
                .foregroundStyle(.green)
                .lineLimit(2)
        case .failed(let msg):
            Label(msg, systemImage: "exclamationmark.triangle.fill")
                .font(.footnote)
                .foregroundStyle(.red)
                .lineLimit(3)
        }
    }

    private func toggle() async {
        switch recorder.state {
        case .recording:
            recorder.stop()
            await persistTake()
        default:
            await beginRecording()
        }
    }

    private func beginRecording() async {
        status = .recording
        locationName = nil
        do {
            try recorder.start()
        } catch {
            status = .failed("Couldn't start recording: \(error.localizedDescription)")
            return
        }
        Task {
            let name = await locationProvider.placeName()
            await MainActor.run { self.locationName = name }
        }
    }

    private func persistTake() async {
        guard let tempURL = recorder.fileURL, let started = recorder.startedAt else {
            status = .failed("Recording produced no file")
            return
        }
        let duration = recorder.elapsed
        let loc = locationName
        recorder.reset()

        let id = UUID()
        let filename = LocalRecordingsStore.makeFilename(date: started, location: loc)
        let rec = LocalRecording(
            id: id,
            filename: filename,
            createdAt: started,
            duration: duration,
            location: loc,
            uploadedAt: nil,
            driveFileID: nil
        )

        let dest = recordings.audioURL(for: rec)
        do {
            // AudioRecorder wrote to a random URL; move it into the canonical recordings dir.
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.moveItem(at: tempURL, to: dest)
            try recordings.save(rec)
            lastSavedFilename = filename
            status = .saved
        } catch {
            status = .failed("Couldn't save: \(error.localizedDescription)")
        }
    }

    private func formatted(_ t: TimeInterval) -> String {
        let total = Int(t)
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%02d:%02d", m, s)
    }
}
