import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var oauth: OAuthSession
    @State private var draftClientID: String = ""
    @State private var draftFolderID: String = ""
    @State private var saved: Bool = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("voice-memo uploads to your own Google Drive via OAuth. Sign-in happens each time you tap Upload in the Library tab. Nothing is stored across app restarts.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section {
                    TextField("123…-abc.apps.googleusercontent.com", text: $draftClientID, axis: .vertical)
                        .lineLimit(1...3)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .font(.system(.footnote, design: .monospaced))
                } header: {
                    Text("OAuth Client ID (iOS)")
                } footer: {
                    Text("In Google Cloud Console: APIs & Services → Credentials → Create OAuth client ID → iOS. Paste the client ID here (no client secret needed — PKCE is used).")
                }

                Section {
                    TextField("e.g. 1AbC…xyz", text: $draftFolderID)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } header: {
                    Text("Destination Folder ID")
                } footer: {
                    Text("Open the target folder in Google Drive in a browser. The ID is the part of the URL after /folders/.")
                }

                Section {
                    Button {
                        settings.clientID = draftClientID
                        settings.folderID = draftFolderID
                        oauth.clear()
                        saved = true
                    } label: {
                        Text("Save").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(draftClientID.isEmpty || draftFolderID.isEmpty)

                    if saved {
                        Label("Saved", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }

                Section {
                    Button(role: .destructive) {
                        oauth.clear()
                    } label: {
                        Label("Sign out (clear in-memory token)", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                    .disabled(oauth.accessToken == nil)
                } footer: {
                    Text("OAuth tokens live only in memory and are wiped on app restart.")
                }
            }
            .navigationTitle("Settings")
            .onAppear {
                draftClientID = settings.clientID
                draftFolderID = settings.folderID
            }
        }
    }
}
