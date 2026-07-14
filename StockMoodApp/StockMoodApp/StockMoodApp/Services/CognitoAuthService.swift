import Foundation
import AuthenticationServices
import CryptoKit
import UIKit

// MARK: - CognitoAuthService
// Sign-in against the AWS Cognito User Pool via the Hosted UI
// (authorization-code + PKCE over ASWebAuthenticationSession — no SDK).
//
// The Cognito access token goes into KeychainStore.sessionToken, so APIClient
// sends it as `Authorization: Bearer …` unchanged; the backend verifies it
// against the pool's JWKS and resolves the user as "cognito-<sub>".
// The refresh token is kept separately and used to renew the access token
// silently (on launch and on the first 401).

enum CognitoAuthError: Error, LocalizedError {
    case cancelled
    case invalidCallback
    case tokenExchangeFailed(String)

    var errorDescription: String? {
        switch self {
        case .cancelled: return "登入已取消"
        case .invalidCallback: return "登入回應格式錯誤"
        case .tokenExchangeFailed(let detail): return "登入憑證交換失敗：\(detail)"
        }
    }
}

final class CognitoAuthService: NSObject {

    static let shared = CognitoAuthService()

    // Deployed values (StockMood-Cognito stack outputs). Overridable for other
    // environments via UserDefaults, same pattern as APIClient's api_base_url.
    private let domain = UserDefaults.standard.string(forKey: "cognito_domain")
        ?? "https://stockmood-hackathon.auth.us-east-1.amazoncognito.com"
    private let clientId = UserDefaults.standard.string(forKey: "cognito_client_id")
        ?? "5o8p6epjnt18rcjmniimilan6r"
    private let redirectURI = "stockmoodapp://callback"
    private let callbackScheme = "stockmoodapp"

    struct Session {
        let userId: String      // "cognito-<sub>", matches what the backend resolves
        let email: String?
    }

    private override init() { super.init() }

    // MARK: - Hosted UI sign-in (authorization code + PKCE)

    /// - Parameter identityProvider: pass "Google" / "SignInWithApple" to skip
    ///   the Hosted UI chooser and go straight to that federated IdP; nil shows
    ///   the pool's own email/password form.
    @MainActor
    func signIn(identityProvider: String? = nil) async throws -> Session {
        let verifier = Self.randomURLSafeString(bytes: 32)
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncodedString()
        let state = Self.randomURLSafeString(bytes: 16)

        var components = URLComponents(string: "\(domain)/oauth2/authorize")!
        var queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: "openid email profile"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: challenge),
        ]
        if let idp = identityProvider {
            components.queryItems?.append(URLQueryItem(name: "identity_provider", value: idp))
        }

        let callbackURL = try await presentWebAuth(url: components.url!)

        guard let items = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems,
              items.first(where: { $0.name == "state" })?.value == state,
              let code = items.first(where: { $0.name == "code" })?.value else {
            throw CognitoAuthError.invalidCallback
        }

        let tokens = try await exchangeToken(form: [
            "grant_type": "authorization_code",
            "client_id": clientId,
            "code": code,
            "redirect_uri": redirectURI,
            "code_verifier": verifier,
        ])
        return try storeSession(tokens)
    }

    /// Renew the access token with the stored refresh token. Returns false when
    /// there is nothing to refresh or Cognito rejects it (e.g. token revoked).
    func refreshSession() async -> Bool {
        guard let refreshToken = KeychainStore.shared.cognitoRefreshToken else { return false }
        do {
            let tokens = try await exchangeToken(form: [
                "grant_type": "refresh_token",
                "client_id": clientId,
                "refresh_token": refreshToken,
            ])
            _ = try storeSession(tokens)
            return true
        } catch {
            print("CognitoAuthService: refresh failed: \(error.localizedDescription)")
            return false
        }
    }

    /// Launch-time hygiene: renew ahead of expiry so the first API call
    /// doesn't eat a 401 round-trip.
    func refreshIfNeeded() async {
        guard KeychainStore.shared.cognitoRefreshToken != nil else { return }
        if let expiry = KeychainStore.shared.cognitoTokenExpiry,
           expiry.timeIntervalSinceNow > 120 { return }  // still comfortably valid
        _ = await refreshSession()
    }

    func clearSession() {
        KeychainStore.shared.cognitoRefreshToken = nil
        KeychainStore.shared.cognitoTokenExpiry = nil
    }

    // MARK: - Internals

    @MainActor
    private func presentWebAuth(url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: callbackScheme) { callbackURL, error in
                if let error = error {
                    let nsError = error as NSError
                    if nsError.domain == ASWebAuthenticationSessionError.errorDomain,
                       nsError.code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                        continuation.resume(throwing: CognitoAuthError.cancelled)
                    } else {
                        continuation.resume(throwing: error)
                    }
                    return
                }
                guard let callbackURL = callbackURL else {
                    continuation.resume(throwing: CognitoAuthError.invalidCallback)
                    return
                }
                continuation.resume(returning: callbackURL)
            }
            session.presentationContextProvider = self
            // Ephemeral: no shared Hosted-UI cookie, so app 登出後不會被自動登回同帳號
            session.prefersEphemeralWebBrowserSession = true
            session.start()
        }
    }

    private struct TokenResponse: Decodable {
        let access_token: String
        let id_token: String?
        let refresh_token: String?   // absent on refresh_token grant
        let expires_in: Int
    }

    private func exchangeToken(form: [String: String]) async throws -> TokenResponse {
        var request = URLRequest(url: URL(string: "\(domain)/oauth2/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = form
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw CognitoAuthError.tokenExchangeFailed("HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1) \(body)")
        }
        return try JSONDecoder().decode(TokenResponse.self, from: data)
    }

    /// Persist tokens and derive the app-side user identity from the JWT claims.
    private func storeSession(_ tokens: TokenResponse) throws -> Session {
        guard let claims = Self.decodeJWTPayload(tokens.access_token),
              let sub = claims["sub"] as? String else {
            throw CognitoAuthError.tokenExchangeFailed("access token 缺少 sub")
        }
        KeychainStore.shared.sessionToken = tokens.access_token
        if let refresh = tokens.refresh_token {
            KeychainStore.shared.cognitoRefreshToken = refresh
        }
        KeychainStore.shared.cognitoTokenExpiry = Date().addingTimeInterval(TimeInterval(tokens.expires_in))

        // email lives in the id token, not the access token
        let email = tokens.id_token.flatMap { Self.decodeJWTPayload($0)?["email"] as? String }
        return Session(userId: "cognito-\(sub)", email: email)
    }

    // MARK: - Small helpers

    private static func randomURLSafeString(bytes count: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: count)
        _ = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        return Data(bytes).base64URLEncodedString()
    }

    /// Decode a JWT's payload segment without verifying it (verification is the
    /// backend's job; we only need sub/email for local display and scoping).
    static func decodeJWTPayload(_ jwt: String) -> [String: Any]? {
        let segments = jwt.components(separatedBy: ".")
        guard segments.count >= 2 else { return nil }
        var base64 = segments[1]
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }
        guard let data = Data(base64Encoded: base64) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}

extension CognitoAuthService: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
}

private extension Data {
    /// Base64URL without padding (RFC 7636 requires this form for PKCE values).
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
