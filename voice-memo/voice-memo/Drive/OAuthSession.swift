import AuthenticationServices
import Foundation
import UIKit

enum OAuthError: LocalizedError {
    case invalidClientID
    case userCancelled
    case missingCode
    case tokenExchangeFailed(Int, String)
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .invalidClientID: "Client ID must end with .apps.googleusercontent.com"
        case .userCancelled: "Sign-in cancelled"
        case .missingCode: "No authorization code returned"
        case .tokenExchangeFailed(let status, let body): "Token exchange failed (\(status)): \(body)"
        case .unknown(let s): s
        }
    }
}

/// In-memory OAuth state. Token lives only for this object's lifetime.
/// A fresh OAuthSession is created on every app launch, so tokens never persist across restarts.
@MainActor
final class OAuthSession: NSObject, ObservableObject {
    private(set) var accessToken: String?
    private var presenter: PresentationContextProvider?

    /// Discard any cached token and run the auth flow again.
    func reauthorize(config: OAuthConfig) async throws -> String {
        accessToken = nil
        return try await authorize(config: config)
    }

    /// Return the cached token, or run the auth flow if none.
    func authorize(config: OAuthConfig) async throws -> String {
        if let t = accessToken { return t }
        guard let reversed = config.reversedClientID,
              let redirect = config.redirectURI else {
            throw OAuthError.invalidClientID
        }

        let verifier = PKCE.makeCodeVerifier()
        let challenge = PKCE.challenge(for: verifier)

        var comps = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        comps.queryItems = [
            .init(name: "client_id", value: config.clientID),
            .init(name: "redirect_uri", value: redirect),
            .init(name: "response_type", value: "code"),
            .init(name: "scope", value: "https://www.googleapis.com/auth/drive.file"),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "access_type", value: "online"),
            .init(name: "prompt", value: "select_account"),
        ]

        let callbackURL = try await runWebAuth(url: comps.url!, callbackScheme: reversed)
        guard let code = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "code" })?.value
        else { throw OAuthError.missingCode }

        let token = try await exchangeCode(code, verifier: verifier, config: config, redirect: redirect)
        accessToken = token
        return token
    }

    func clear() { accessToken = nil }

    private func runWebAuth(url: URL, callbackScheme: String) async throws -> URL {
        let presenter = PresentationContextProvider()
        self.presenter = presenter
        return try await withCheckedThrowingContinuation { c in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: callbackScheme
            ) { url, error in
                if let error {
                    let nsErr = error as NSError
                    if nsErr.domain == ASWebAuthenticationSessionError.errorDomain,
                       nsErr.code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                        c.resume(throwing: OAuthError.userCancelled)
                    } else {
                        c.resume(throwing: OAuthError.unknown(error.localizedDescription))
                    }
                    return
                }
                guard let url else {
                    c.resume(throwing: OAuthError.unknown("no callback url"))
                    return
                }
                c.resume(returning: url)
            }
            session.presentationContextProvider = presenter
            session.prefersEphemeralWebBrowserSession = true
            session.start()
        }
    }

    private func exchangeCode(
        _ code: String,
        verifier: String,
        config: OAuthConfig,
        redirect: String
    ) async throws -> String {
        var req = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = [
            "client_id": config.clientID,
            "code": code,
            "code_verifier": verifier,
            "grant_type": "authorization_code",
            "redirect_uri": redirect,
        ]
        req.httpBody = body
            .map { "\($0.key)=\(urlEncode($0.value))" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw OAuthError.unknown("malformed response") }
        guard (200..<300).contains(http.statusCode) else {
            throw OAuthError.tokenExchangeFailed(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        struct Resp: Decodable { let access_token: String }
        return try JSONDecoder().decode(Resp.self, from: data).access_token
    }

    private func urlEncode(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? s
    }
}

private final class PresentationContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
}
