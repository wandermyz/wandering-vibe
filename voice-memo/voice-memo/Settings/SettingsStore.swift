import Combine
import Foundation

@MainActor
final class SettingsStore: ObservableObject {
    private enum Keys {
        static let clientID = "oauth_client_id"
        static let folderID = "drive_folder_id"
    }

    @Published var clientID: String {
        didSet { UserDefaults.standard.set(clientID, forKey: Keys.clientID) }
    }
    @Published var folderID: String {
        didSet { UserDefaults.standard.set(folderID, forKey: Keys.folderID) }
    }

    init() {
        self.clientID = UserDefaults.standard.string(forKey: Keys.clientID) ?? ""
        self.folderID = UserDefaults.standard.string(forKey: Keys.folderID) ?? ""
    }

    var oauthConfig: OAuthConfig? {
        let c = OAuthConfig(clientID: clientID.trimmingCharacters(in: .whitespacesAndNewlines),
                            folderID: folderID.trimmingCharacters(in: .whitespacesAndNewlines))
        return c.isValid ? c : nil
    }

    var isConfigured: Bool { oauthConfig != nil }
}
