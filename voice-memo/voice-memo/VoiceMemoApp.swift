import SwiftUI

@main
struct VoiceMemoApp: App {
    @StateObject private var settings = SettingsStore()
    @StateObject private var recordings = LocalRecordingsStore()
    @StateObject private var oauth = OAuthSession()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(settings)
                .environmentObject(recordings)
                .environmentObject(oauth)
        }
    }
}

struct RootView: View {
    var body: some View {
        TabView {
            RecordView()
                .tabItem { Label("Record", systemImage: "mic.fill") }
            RecordingsListView()
                .tabItem { Label("Library", systemImage: "list.bullet") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}
