import SwiftUI

@main
struct RealSignalMapApp: App {
    @StateObject private var settings: AppSettings
    @StateObject private var recorder: Recorder
    @StateObject private var history: HistoryModel
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let settings = AppSettings()
        let store = SampleStore.shared
        #if DEBUG
        DemoData.seedIfRequested(into: store)
        #endif
        _settings = StateObject(wrappedValue: settings)
        _recorder = StateObject(wrappedValue: Recorder(settings: settings, store: store))
        _history = StateObject(wrappedValue: HistoryModel(store: store))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(settings)
                .environmentObject(recorder)
                .environmentObject(history)
        }
        .onChange(of: scenePhase) { _, phase in
            // Recording is automatic: on whenever the app is in the foreground.
            if phase == .active { recorder.start() } else { recorder.stop() }
        }
    }
}

struct ContentView: View {
    @State private var tab = UserDefaults.standard.integer(forKey: "initialTab") // `-initialTab 1` for screenshots

    var body: some View {
        TabView(selection: $tab) {
            LiveView()
                .tabItem { Label("Live", systemImage: "dot.radiowaves.left.and.right") }
                .tag(0)
            HistoryView()
                .tabItem { Label("History", systemImage: "map") }
                .tag(1)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(2)
        }
    }
}
