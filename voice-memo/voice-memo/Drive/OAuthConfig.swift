import Foundation

struct OAuthConfig: Equatable {
    let clientID: String
    let folderID: String

    var reversedClientID: String? { GoogleClientID.reversed(clientID) }
    var redirectURI: String? {
        guard let r = reversedClientID else { return nil }
        return "\(r):/oauthredirect"
    }

    var isValid: Bool { reversedClientID != nil && !folderID.isEmpty }
}
