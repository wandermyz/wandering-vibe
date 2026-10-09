import CryptoKit
import Foundation

extension Data {
    /// base64url, no padding — per RFC 7515.
    var base64URLEncodedString: String {
        return base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

enum PKCE {
    /// Random code verifier (43–128 unreserved URL-safe chars).
    static func makeCodeVerifier(length: Int = 64) -> String {
        let charset = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        var verifier = ""
        verifier.reserveCapacity(length)
        for _ in 0..<length {
            verifier.append(charset[Int.random(in: 0..<charset.count)])
        }
        return verifier
    }

    /// S256 challenge = base64url(SHA256(verifier))
    static func challenge(for verifier: String) -> String {
        let hash = SHA256.hash(data: Data(verifier.utf8))
        return Data(hash).base64URLEncodedString
    }
}

enum GoogleClientID {
    /// `123456-abc.apps.googleusercontent.com` → `com.googleusercontent.apps.123456-abc`
    static func reversed(_ clientID: String) -> String? {
        let suffix = ".apps.googleusercontent.com"
        guard clientID.hasSuffix(suffix) else { return nil }
        let prefix = clientID.dropLast(suffix.count)
        guard !prefix.isEmpty else { return nil }
        return "com.googleusercontent.apps.\(prefix)"
    }
}
