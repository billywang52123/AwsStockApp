import Foundation
import Security

/// Minimal Keychain wrapper for secrets that must not live in UserDefaults
/// (session tokens etc. — UserDefaults is a plaintext plist).
final class KeychainStore {
    static let shared = KeychainStore()

    static let sessionTokenKey = "session_token"
    static let cognitoRefreshTokenKey = "cognito_refresh_token"
    static let cognitoTokenExpiryKey = "cognito_token_expiry"

    private let service = "com.stockmoodapp.auth"

    private init() {}

    func set(_ value: String, forKey key: String) {
        guard let data = value.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        // Upsert: delete any existing item first, then add
        SecItemDelete(query as CFDictionary)

        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(attributes as CFDictionary, nil)
    }

    func get(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func delete(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Session token convenience

    var sessionToken: String? {
        get { get(Self.sessionTokenKey) }
        set {
            if let token = newValue {
                set(token, forKey: Self.sessionTokenKey)
            } else {
                delete(Self.sessionTokenKey)
            }
        }
    }

    // MARK: - Cognito token convenience

    /// Long-lived Cognito refresh token, used to silently renew the access token.
    var cognitoRefreshToken: String? {
        get { get(Self.cognitoRefreshTokenKey) }
        set {
            if let token = newValue {
                set(token, forKey: Self.cognitoRefreshTokenKey)
            } else {
                delete(Self.cognitoRefreshTokenKey)
            }
        }
    }

    /// Expiry of the current Cognito access token (unix seconds string in keychain).
    var cognitoTokenExpiry: Date? {
        get { get(Self.cognitoTokenExpiryKey).flatMap(Double.init).map(Date.init(timeIntervalSince1970:)) }
        set {
            if let date = newValue {
                set(String(date.timeIntervalSince1970), forKey: Self.cognitoTokenExpiryKey)
            } else {
                delete(Self.cognitoTokenExpiryKey)
            }
        }
    }
}
