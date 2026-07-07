import Foundation

class AppPreferenceStore {
    static let shared = AppPreferenceStore()
    private let onboardingKey = "com.stockmoodapp.onboardingCompleted"
    private let reminderKey = "com.stockmoodapp.reminderSetting"

    private let loginKey = "com.stockmoodapp.isLoggedIn"
    private let userIdKey = "com.stockmoodapp.currentUserId"
    private let guestIdKey = "com.stockmoodapp.guestUserId"

    private init() {}

    // MARK: - User identity

    /// The id of the signed-in user ("apple-…" / "google-…" / "guest-…").
    /// Every per-user store (portfolio, reminders, backend API) is namespaced by this.
    var currentUserId: String {
        get {
            UserDefaults.standard.string(forKey: userIdKey) ?? guestUserId
        }
        set {
            UserDefaults.standard.set(newValue, forKey: userIdKey)
        }
    }

    /// Stable per-device guest id, so the guest path also has its own bucket.
    private var guestUserId: String {
        if let existing = UserDefaults.standard.string(forKey: guestIdKey) {
            return existing
        }
        let generated = "guest-\(UUID().uuidString)"
        UserDefaults.standard.set(generated, forKey: guestIdKey)
        return generated
    }

    /// Sign in as the given user; switches all per-user stores to that user's bucket.
    func signIn(userId: String) {
        currentUserId = userId
        isLoggedIn = true
    }

    /// Continue as guest (訪客路徑) using the stable device guest id.
    func signInAsGuest() {
        currentUserId = guestUserId
        isLoggedIn = true
    }

    func signOut() {
        UserDefaults.standard.removeObject(forKey: userIdKey)
        isLoggedIn = false
        // Drop the API session token so the next account can't reuse it
        KeychainStore.shared.sessionToken = nil
    }

    /// Appends the current user id so each user gets an isolated bucket.
    func userScopedKey(_ baseKey: String) -> String {
        "\(baseKey).\(currentUserId)"
    }

    var isLoggedIn: Bool {
        get {
            UserDefaults.standard.bool(forKey: loginKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: loginKey)
        }
    }

    // Per-user: a different account signing in on this device goes through
    // onboarding (scenario + portfolio input) with its own data
    var isOnboardingCompleted: Bool {
        get {
            UserDefaults.standard.bool(forKey: userScopedKey(onboardingKey))
        }
        set {
            UserDefaults.standard.set(newValue, forKey: userScopedKey(onboardingKey))
        }
    }

    func loadReminderSetting() -> ReminderSetting {
        guard let data = UserDefaults.standard.data(forKey: userScopedKey(reminderKey)) else {
            // Default settings
            let defaultSetting = ReminderSetting(
                enabled: true,
                timeSlot: .evening,
                items: ReminderItems(anxietyScore: true, dailyCard: true, volatilityAlert: false)
            )
            saveReminderSetting(defaultSetting)
            return defaultSetting
        }
        do {
            return try JSONDecoder().decode(ReminderSetting.self, from: data)
        } catch {
            print("Failed to decode reminder settings: \(error)")
            return ReminderSetting(
                enabled: true,
                timeSlot: .evening,
                items: ReminderItems(anxietyScore: true, dailyCard: true, volatilityAlert: false)
            )
        }
    }

    func saveReminderSetting(_ setting: ReminderSetting) {
        do {
            let data = try JSONEncoder().encode(setting)
            UserDefaults.standard.set(data, forKey: userScopedKey(reminderKey))
        } catch {
            print("Failed to encode reminder settings: \(error)")
        }
    }
}
