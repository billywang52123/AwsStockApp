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

    // MARK: - 隱私與安心偏好(spec 05 · 10c,per-user)

    private let blurAmountsKey = "com.stockmoodapp.blurAmountsByDefault"
    private let faceIDLockKey = "com.stockmoodapp.faceIDLockEnabled"

    /// 開 App 時金額預設模糊(眼睛 toggle 的初始狀態)
    var blurAmountsByDefault: Bool {
        get { UserDefaults.standard.bool(forKey: userScopedKey(blurAmountsKey)) }
        set { UserDefaults.standard.set(newValue, forKey: userScopedKey(blurAmountsKey)) }
    }

    /// 進入持股頁需要 Face ID
    var faceIDLockEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: userScopedKey(faceIDLockKey)) }
        set { UserDefaults.standard.set(newValue, forKey: userScopedKey(faceIDLockKey)) }
    }

    /// 一鍵全部刪除後,連本機顯示偏好一起清空(10a)
    func resetPrivacyPreferences() {
        UserDefaults.standard.removeObject(forKey: userScopedKey(blurAmountsKey))
        UserDefaults.standard.removeObject(forKey: userScopedKey(faceIDLockKey))
    }

    // MARK: - 每日抽卡包(spec 06,per-user)

    private let skipPackAnimationKey = "com.stockmoodapp.alwaysSkipPackAnimation"
    private let regeneratePackAfterSimDateKey = "com.stockmoodapp.regeneratePackAfterSimDate"

    /// 「總是跳過開包動畫」:開啟後點「開啟今日卡包」直達 15e 完成態
    var alwaysSkipPackAnimation: Bool {
        get { UserDefaults.standard.bool(forKey: userScopedKey(skipPackAnimationKey)) }
        set { UserDefaults.standard.set(newValue, forKey: userScopedKey(skipPackAnimationKey)) }
    }

    /// 日期切換事件若發生在抽卡分頁尚未建立時，保留一次 force 重生需求。
    var shouldRegeneratePackAfterSimDateChange: Bool {
        get { UserDefaults.standard.bool(forKey: userScopedKey(regeneratePackAfterSimDateKey)) }
        set { UserDefaults.standard.set(newValue, forKey: userScopedKey(regeneratePackAfterSimDateKey)) }
    }

    // MARK: - 抽籤通知(日間/夜間收盤,per-user)

    private let fortuneDayNotifyKey = "com.stockmoodapp.fortuneNotify.dayClose"
    private let fortuneNightNotifyKey = "com.stockmoodapp.fortuneNotify.nightClose"

    /// 日間收盤求籤通知(台灣時間 13:30)
    var fortuneDayCloseNotifyEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: userScopedKey(fortuneDayNotifyKey)) }
        set { UserDefaults.standard.set(newValue, forKey: userScopedKey(fortuneDayNotifyKey)) }
    }

    /// 夜間收盤求籤通知(次日台灣時間 05:00)
    var fortuneNightCloseNotifyEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: userScopedKey(fortuneNightNotifyKey)) }
        set { UserDefaults.standard.set(newValue, forKey: userScopedKey(fortuneNightNotifyKey)) }
    }

    // MARK: - 18b 首頁風格測驗提醒卡(spec 07,per-user)

    private let styleNudgeDismissedKey = "com.stockmoodapp.styleNudgeDismissedAt"

    /// 關閉提醒卡的時間;7 天內 `shouldShowStyleNudge == false`
    var styleNudgeDismissedAt: Date? {
        get { UserDefaults.standard.object(forKey: userScopedKey(styleNudgeDismissedKey)) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: userScopedKey(styleNudgeDismissedKey)) }
    }

    /// 18b:提醒卡是否已過 7 天冷卻期(未關閉過 = 可顯示)
    var shouldShowStyleNudge: Bool {
        guard let dismissedAt = styleNudgeDismissedAt else { return true }
        return Date().timeIntervalSince(dismissedAt) > 7 * 24 * 60 * 60
    }

    // Per-user: a different account signing in on this device goes through
    // onboarding (style quiz + portfolio input) with its own data
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
