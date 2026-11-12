import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var history: HistoryModel
    @State private var stats: SampleStore.Stats?
    @State private var confirmDelete = false
    @State private var urlDraft = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://…", text: $urlDraft)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit { settings.probeURL = urlDraft }
                    LabeledContent("Every", value: "\(Int(AppSettings.interval)) s or \(Int(AppSettings.distance)) m")
                    Picker("Timeout (= no internet)", selection: $settings.timeout) {
                        ForEach(AppSettings.timeoutChoices, id: \.self) { Text("\(Int($0)) s").tag($0) }
                    }
                    LabeledContent("Network", value: "Cellular only")
                } header: {
                    Text("Probe")
                } footer: {
                    Text("Each probe is an HTTPS request on a kept-alive connection, forced over the cellular radio even when Wi‑Fi is connected. Latency = request round-trip; reconnects are timed separately. Changes apply next time the app comes to the foreground.")
                }

                Section {
                    Picker("Max points", selection: $settings.maxPoints) {
                        ForEach(AppSettings.capChoices, id: \.self) { Text($0.formatted()).tag($0) }
                    }
                    if let stats {
                        VStack(alignment: .leading, spacing: 6) {
                            ProgressView(value: min(1, Double(stats.count) / Double(settings.maxPoints)))
                            Text(usageText(stats)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Storage")
                } footer: {
                    Text("When full, the oldest points are discarded first.")
                }

                Section {
                    Button("Delete all data…", role: .destructive) { confirmDelete = true }
                }
            }
            .navigationTitle("Settings")
            .confirmationDialog("Delete all recorded points?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete all", role: .destructive) {
                    SampleStore.shared.deleteAll()
                    refresh()
                    history.refreshAll()
                }
            }
        }
        .onAppear {
            urlDraft = settings.probeURL
            refresh()
        }
        .onDisappear { if urlDraft != settings.probeURL { settings.probeURL = urlDraft } }
        .onChange(of: settings.maxPoints) { _, cap in
            DispatchQueue.global(qos: .utility).async {
                SampleStore.shared.enforceCap(cap)
                DispatchQueue.main.async { refresh() }
            }
        }
    }

    private func refresh() {
        DispatchQueue.global(qos: .utility).async {
            let s = SampleStore.shared.stats()
            DispatchQueue.main.async { stats = s }
        }
    }

    private func usageText(_ s: SampleStore.Stats) -> String {
        var parts = ["\(s.count.formatted()) used",
                     ByteCountFormatter.string(fromByteCount: s.bytes, countStyle: .file)]
        if let oldest = s.oldest { parts.append("oldest \(oldest.formatted(date: .abbreviated, time: .omitted))") }
        return parts.joined(separator: " · ")
    }
}
