import Foundation
import Combine
import AuthenticationServices
import GoogleSignIn
import UIKit

// MARK: - AuthService
// Centralised service that handles:
// 1. Apple Sign-In (native ASAuthorizationController) + sends identity token to backend
// 2. Google Sign-In (via GoogleSignIn SDK v9) + sends id token to backend
// 3. Persisting local session state

@MainActor
final class AuthService: ObservableObject {

    static let shared = AuthService()

    @Published var isAuthenticating = false
    @Published var authError: String? = nil

    private init() {}

    /// True when the reversed-client-id URL scheme is present in Info.plist,
    /// which GIDSignIn requires before it will start the OAuth flow.
    private static func isGoogleURLSchemeRegistered() -> Bool {
        guard let clientID = GIDSignIn.sharedInstance.configuration?.clientID else { return false }
        let expectedScheme = clientID
            .components(separatedBy: ".")
            .reversed()
            .joined(separator: ".")
        guard let urlTypes = Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]] else {
            return false
        }
        return urlTypes.contains { type in
            (type["CFBundleURLSchemes"] as? [String])?.contains(expectedScheme) == true
        }
    }

    // MARK: - Apple Sign-In

    /// Call from LoginView's SignInWithAppleButton onCompletion handler.
    func handleAppleCompletion(_ result: Result<ASAuthorization, Error>, onSuccess: @escaping () -> Void) {
        switch result {
        case .success(let auth):
            guard let credential = auth.credential as? ASAuthorizationAppleIDCredential else {
                authError = "Apple 憑證格式錯誤"
                return
            }
            Task {
                await sendAppleTokenToBackend(credential: credential, onSuccess: onSuccess)
            }
        case .failure(let error):
            let nsError = error as NSError
            // Code 1001 = user cancelled — don't show error UI
            if nsError.code != 1001 {
                authError = "Apple 登入失敗：\(error.localizedDescription)"
                HapticManager.shared.triggerNotification(type: .error)
            }
        }
    }

    private func sendAppleTokenToBackend(credential: ASAuthorizationAppleIDCredential, onSuccess: @escaping () -> Void) async {
        isAuthenticating = true
        authError = nil

        do {
            guard let identityTokenData = credential.identityToken,
                  let identityToken = String(data: identityTokenData, encoding: .utf8) else {
                throw URLError(.badServerResponse)
            }

            struct AppleAuthRequest: Encodable {
                let identity_token: String
                let user_id: String
                let full_name: String?
                let email: String?
            }
            let fullName = [credential.fullName?.givenName, credential.fullName?.familyName]
                .compactMap { $0 }.joined(separator: " ")

            let body = AppleAuthRequest(
                identity_token: identityToken,
                user_id: credential.user,
                full_name: fullName.isEmpty ? nil : fullName,
                email: credential.email
            )

            let session: [String: String] = try await APIClient.shared.requestBody("/auth/apple", method: "POST", body: body)
            Self.storeSessionToken(from: session)
        } catch {
            // Offline / legacy backend — continue with local session; requests
            // fall back to the X-User-Id header until a token is obtained.
            print("AuthService: Apple backend verify skipped: \(error.localizedDescription)")
        }

        // credential.user is Apple's stable per-app user identifier
        AppPreferenceStore.shared.signIn(userId: "apple-\(credential.user)")
        PushDeviceService.shared.registerForRemoteNotificationsIfPermitted()
        PushDeviceService.shared.applyPendingRegistration()
        HapticManager.shared.triggerNotification(type: .success)
        isAuthenticating = false
        onSuccess()
    }

    // MARK: - Google Sign-In (GoogleSignIn SDK v9)

    func signInWithGoogle(onSuccess: @escaping () -> Void) {
        isAuthenticating = true
        authError = nil

        // Guard: GIDSignIn throws an uncatchable NSException (app crash) if the
        // clientID configuration or the reversed-client-id URL scheme is missing.
        guard GIDSignIn.sharedInstance.configuration != nil else {
            authError = "Google 登入尚未設定完成（缺少 GoogleService-Info.plist），請改用其他方式登入"
            isAuthenticating = false
            return
        }
        guard Self.isGoogleURLSchemeRegistered() else {
            authError = "Google 登入尚未設定完成（缺少 URL Scheme），請改用其他方式登入"
            isAuthenticating = false
            return
        }

        // Get the root view controller to present the Google sign-in UI
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = windowScene.windows.first(where: { $0.isKeyWindow })?.rootViewController else {
            authError = "無法取得視窗，請重試"
            isAuthenticating = false
            return
        }

        GIDSignIn.sharedInstance.signIn(withPresenting: rootVC) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self = self else { return }

                if let error = error {
                    // GIDSignInError.Code 1 = user cancelled
                    let nsError = error as NSError
                    if nsError.code != -5 {   // GIDSignInError.canceled
                        self.authError = "Google 登入失敗：\(error.localizedDescription)"
                        HapticManager.shared.triggerNotification(type: .error)
                    }
                    self.isAuthenticating = false
                    return
                }

                guard let result = result,
                      let idToken = result.user.idToken?.tokenString else {
                    self.authError = "Google 無法取得 ID Token"
                    self.isAuthenticating = false
                    return
                }

                let email = result.user.profile?.email
                let name = result.user.profile?.name
                print("Google Sign-In Success: \(email ?? "unknown")")

                await self.sendGoogleTokenToBackend(
                    idToken: idToken,
                    userID: result.user.userID,
                    email: email,
                    name: name,
                    onSuccess: onSuccess
                )
            }
        }
    }

    private func sendGoogleTokenToBackend(idToken: String, userID: String?, email: String?, name: String?, onSuccess: @escaping () -> Void) async {
        do {
            struct GoogleAuthRequest: Encodable {
                let id_token: String
                let email: String?
                let name: String?
            }
            let body = GoogleAuthRequest(id_token: idToken, email: email, name: name)
            let session: [String: String] = try await APIClient.shared.requestBody("/auth/google", method: "POST", body: body)
            Self.storeSessionToken(from: session)
        } catch {
            // Offline / legacy backend — continue with local session; requests
            // fall back to the X-User-Id header until a token is obtained.
            print("AuthService: Google backend token exchange skipped: \(error.localizedDescription)")
        }

        // Google's stable subject id; fall back to email if the SDK didn't return one
        let stableId = userID ?? email ?? UUID().uuidString
        AppPreferenceStore.shared.signIn(userId: "google-\(stableId)")
        PushDeviceService.shared.registerForRemoteNotificationsIfPermitted()
        PushDeviceService.shared.applyPendingRegistration()
        HapticManager.shared.triggerNotification(type: .success)
        isAuthenticating = false
        onSuccess()
    }

    // MARK: - Cognito (Hosted UI email / password)

    /// Sign in via the Cognito Hosted UI. The obtained access token replaces the
    /// legacy self-issued session JWT — APIClient sends it as Bearer unchanged,
    /// and the backend resolves the user as "cognito-<sub>".
    func signInWithCognito(onSuccess: @escaping () -> Void) {
        isAuthenticating = true
        authError = nil
        Task {
            do {
                let session = try await CognitoAuthService.shared.signIn()
                AppPreferenceStore.shared.signIn(userId: session.userId)
                PushDeviceService.shared.registerForRemoteNotificationsIfPermitted()
                PushDeviceService.shared.applyPendingRegistration()
                HapticManager.shared.triggerNotification(type: .success)
                isAuthenticating = false
                onSuccess()
            } catch CognitoAuthError.cancelled {
                // User dismissed the sheet — not an error state
                isAuthenticating = false
            } catch {
                authError = "登入失敗：\(error.localizedDescription)"
                HapticManager.shared.triggerNotification(type: .error)
                isAuthenticating = false
            }
        }
    }

    // MARK: - Guest session

    /// Sign in locally as guest and register the guest id with the backend to
    /// obtain a session token. Works offline — the token fetch is best-effort.
    func signInAsGuest() {
        AppPreferenceStore.shared.signInAsGuest()
        Task { await self.registerGuestSession() }
    }

    private func registerGuestSession() async {
        struct GuestAuthRequest: Encodable {
            let guest_id: String
        }
        do {
            let body = GuestAuthRequest(guest_id: AppPreferenceStore.shared.currentUserId)
            let session: [String: String] = try await APIClient.shared.requestBody("/auth/guest", method: "POST", body: body)
            Self.storeSessionToken(from: session)
            PushDeviceService.shared.applyPendingRegistration()
        } catch {
            print("AuthService: guest session registration skipped: \(error.localizedDescription)")
        }
    }

    /// Called on app launch: if we're logged in but have no session token yet
    /// (upgrade from an older build, or the token expired), try to get one.
    /// Guests can re-register silently; Apple/Google users keep using the
    /// legacy header until they sign in again.
    func ensureSessionToken() async {
        guard AppPreferenceStore.shared.isLoggedIn else { return }
        let userId = AppPreferenceStore.shared.currentUserId
        if userId.hasPrefix("cognito-") {
            // Cognito access tokens last 1h — renew silently ahead of expiry.
            await CognitoAuthService.shared.refreshIfNeeded()
            return
        }
        guard KeychainStore.shared.sessionToken == nil,
              userId.hasPrefix("guest-") else { return }
        await registerGuestSession()
    }

    // MARK: - Returning-user check(換機/重裝後不再問初次設定)

    /// 雲端已有這個帳號的資料(持股或觀察清單)就視為老用戶;
    /// 本機 onboarding 旗標遺失(重裝、換機)時用這個補判,不再重問初次問題。
    func hasExistingRemoteData() async -> Bool {
        if let items: [PortfolioItem] = try? await APIClient.shared.request("/portfolio/items", method: "GET"),
           !items.isEmpty {
            return true
        }
        if let index: WatchlistIndex = try? await APIClient.shared.request("/watchlists", method: "GET"),
           index.holdingCount > 0 || !index.watchlists.isEmpty {
            return true
        }
        return false
    }

    // MARK: - Sign out

    /// 登出:清掉本機登入狀態與 session token,回登入頁。
    /// 雲端資料不動,重新登入同一帳號即可找回;訪客 id 也保留在裝置上。
    func signOut() {
        // 先解除本裝置的推播註冊（需在清除 session token 前發出，才帶得到 Authorization）。
        Task { await PushDeviceService.shared.unregisterCurrentDevice() }
        if GIDSignIn.sharedInstance.currentUser != nil {
            GIDSignIn.sharedInstance.signOut()
        }
        CognitoAuthService.shared.clearSession()
        AppPreferenceStore.shared.signOut()
        NotificationCenter.default.post(name: .authSessionDidEnd, object: nil)
    }

    // MARK: - Session token storage

    private static func storeSessionToken(from response: [String: String]) {
        guard let token = response["access_token"], !token.isEmpty else { return }
        KeychainStore.shared.sessionToken = token
    }
}

extension Notification.Name {
    /// 登出完成:AppRouter 收到後切回登入頁
    static let authSessionDidEnd = Notification.Name("com.stockmoodapp.authSessionDidEnd")
}
