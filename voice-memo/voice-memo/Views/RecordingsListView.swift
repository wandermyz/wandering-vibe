import SwiftUI

struct RecordingsListView: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var recordings: LocalRecordingsStore
    @EnvironmentObject private var oauth: OAuthSession

    @State private var syncing = false
    @State private var syncStatus: String?
    @State private var syncError: String?

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Library")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            Task { await upload() }
                        } label: {
                            if syncing {
                                ProgressView()
                            } else {
                                Label("Upload", systemImage: "icloud.and.arrow.up")
                            }
                        }
                        .disabled(syncing || !settings.isConfigured || pendingCount == 0)
                    }
                }
                .safeAreaInset(edge: .bottom) { footer }
        }
    }

    private var pendingCount: Int {
        recordings.recordings.filter { $0.uploadedAt == nil }.count
    }

    @ViewBuilder
    private var content: some View {
        if recordings.recordings.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "mic.slash").font(.largeTitle).foregroundStyle(.secondary)
                Text("No recordings yet").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(grouped, id: \.month) { group in
                    Section(monthHeader(group.month)) {
                        ForEach(group.items) { rec in
                            FileRow(rec: rec)
                                .swipeActions {
                                    Button(role: .destructive) {
                                        recordings.delete(rec)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var footer: some View {
        VStack(spacing: 4) {
            if let syncError {
                Label(syncError, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .lineLimit(3)
                    .padding(.horizontal)
            } else if let syncStatus {
                Text(syncStatus)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            } else if !settings.isConfigured {
                Text("Configure Settings to enable upload.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.bottom, 4)
    }

    private var grouped: [(month: String, items: [LocalRecording])] {
        let dict = Dictionary(grouping: recordings.recordings, by: { $0.monthFolderName })
        return dict.keys.sorted(by: >).map { ($0, dict[$0]!.sorted(by: { $0.createdAt > $1.createdAt })) }
    }

    private func monthHeader(_ s: String) -> String {
        guard s.count == 6, let y = Int(s.prefix(4)), let m = Int(s.suffix(2)) else { return s }
        var c = DateComponents(); c.year = y; c.month = m; c.day = 1
        guard let d = Calendar(identifier: .gregorian).date(from: c) else { return s }
        let f = DateFormatter(); f.dateFormat = "LLLL yyyy"
        return f.string(from: d)
    }

    private func upload() async {
        guard let config = settings.oauthConfig else {
            syncError = "Configure Settings first."
            return
        }
        syncing = true
        syncError = nil
        syncStatus = "Signing in…"
        defer { syncing = false }

        do {
            // Per requirements: OAuth happens each time the user triggers an upload.
            let token = try await oauth.reauthorize(config: config)
            let client = DriveClient(tokenProvider: { token })

            let pending = recordings.recordings.filter { $0.uploadedAt == nil }
            guard !pending.isEmpty else {
                syncStatus = "Nothing to upload."
                return
            }

            // Group pending recordings by month folder, then diff against Drive contents.
            let byMonth = Dictionary(grouping: pending, by: { $0.monthFolderName })
            var uploaded = 0
            var skipped = 0

            for (month, items) in byMonth.sorted(by: { $0.key < $1.key }) {
                syncStatus = "Checking \(month)…"
                let parent = try await client.ensureFolder(named: month, parent: config.folderID)
                let existing = try await client.filenames(in: parent)
                for rec in items {
                    if existing.contains(rec.filename) {
                        skipped += 1
                        continue
                    }
                    syncStatus = "Uploading \(rec.filename)…"
                    let url = recordings.audioURL(for: rec)
                    let driveID = try await client.upload(
                        fileURL: url,
                        name: rec.filename,
                        parent: parent,
                        createdAt: rec.createdAt,
                        durationSec: rec.duration
                    )
                    try recordings.markUploaded(rec, driveFileID: driveID)
                    uploaded += 1
                }
            }

            syncStatus = "Uploaded \(uploaded), already in Drive: \(skipped)."
        } catch {
            syncError = error.localizedDescription
            syncStatus = nil
        }
    }
}

private struct FileRow: View {
    let rec: LocalRecording

    var body: some View {
        HStack(spacing: 12) {
            statusIcon
            VStack(alignment: .leading, spacing: 4) {
                Text(rec.filename)
                    .font(.body)
                    .lineLimit(1)
                HStack(spacing: 12) {
                    Text(rec.createdAt, format: .dateTime.year().month().day().hour().minute())
                    Text(formatDuration(rec.duration))
                    if let loc = rec.location, !loc.isEmpty {
                        Text(loc).lineLimit(1)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var statusIcon: some View {
        if rec.uploadedAt != nil {
            Image(systemName: "checkmark.icloud.fill")
                .foregroundStyle(.green)
        } else {
            Image(systemName: "icloud.slash")
                .foregroundStyle(.secondary)
        }
    }

    private func formatDuration(_ t: Double) -> String {
        let total = Int(t)
        let m = total / 60, s = total % 60
        return String(format: "%d:%02d", m, s)
    }
}
