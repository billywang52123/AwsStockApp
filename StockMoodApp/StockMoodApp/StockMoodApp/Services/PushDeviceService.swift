import Foundation
import UIKit
import UserNotifications

// MARK: - API Models

/// POST /push-devices 的 request body。
/// APIClient 使用 .convertFromSnakeCase，所以 Swift 的 deviceToken 會送成 device_token。
struct PushDeviceRegisterRequest: Encodable {
    let deviceToken: String
    let platform = "ios"
    let environment: String
}

/// 後端回傳的裝置註冊結果（已被 APIClient 拆掉最外層 success/data wrapper）。
struct PushDeviceRegistration: Codable {
    let id: String
    let platform: String
    let environment: String
    let enabled: Bool
    let registrationStatus: String   // "pending_sns_configuration" | "active"
    // 後端可能回傳帶時區尾綴(+00:00 / Z)的時間字串，APIClient 的日期解碼器
    // 不吃這種格式；此欄位 App 只需保留原字串，不做運算，故用 String 避免解碼失敗。
    let lastRegisteredAt: String
}

/// 負責把 APNs device token 傳到後端 ECS。
///
/// 流程：APNs 回傳 token -> handleNewToken() -> 若已登入直接上傳，
/// 未登入則先快取，登入完成後由 applyPendingRegistration() 補傳。
/// iOS 不直接呼叫 SNS，也不持有任何 AWS 金鑰。
final class PushDeviceService {
    static let shared = PushDeviceService()
    private init() {}

    private enum Keys {
        static let pendingToken = "push.pendingDeviceToken"
        static let registeredDeviceId = "push.registeredDeviceId"
    }

    /// 目前這台裝置由後端配發的 device id（DELETE 解除註冊時用）。
    private(set) var registeredDeviceId: String? {
        get { UserDefaults.standard.string(forKey: Keys.registeredDeviceId) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.registeredDeviceId) }
    }

    /// 最近一次 APNs 回傳的 token；登入後補傳、或每次啟動重傳都靠它。
    private var lastDeviceToken: String? {
        get { UserDefaults.standard.string(forKey: Keys.pendingToken) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.pendingToken) }
    }

    /// Xcode Development build -> sandbox；TestFlight / App Store -> production。
    private var environment: String {
        #if DEBUG
        return "sandbox"
        #else
        return "production"
        #endif
    }

    // MARK: - Public entry points

    /// AppDelegate 收到新的 APNs token 時呼叫。
    /// 每次 APNs 回傳 token 都可安全呼叫（後端採 upsert，不會產生重複裝置）。
    func handleNewToken(_ token: String) {
        lastDeviceToken = token
        Task { await uploadIfPossible() }
    }

    /// 登入成功後呼叫，補傳先前 APNs 已回傳、但當時尚未登入的 token。
    func applyPendingRegistration() {
        guard lastDeviceToken != nil else { return }
        Task { await uploadIfPossible() }
    }

    /// 若通知權限已授權，向 APNs 註冊以取得 device token。
    /// 建議在登入成功或使用者開啟推播設定後呼叫。
    func registerForRemoteNotificationsIfPermitted() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized ||
                    settings.authorizationStatus == .provisional else { return }
            DispatchQueue.main.async {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
    }

    /// 登出時解除本裝置註冊，避免共用裝置的下一位使用者收到前一位的個人化通知。
    func unregisterCurrentDevice() async {
        guard let deviceId = registeredDeviceId else { return }
        do {
            let _: PushDeviceRegistration? = try? await APIClient.shared.request(
                "/push-devices/\(deviceId)",
                method: "DELETE"
            )
            registeredDeviceId = nil
        }
    }

    // MARK: - Diagnostic (設定頁「測試遠端推播」按鈕用)

    /// 手動觸發一次遠端推播鏈路檢查，回傳給 UI 顯示的人類可讀訊息。
    /// 沒 token 時先向 APNs 要，請使用者幾秒後再按一次。
    @MainActor
    func runRemotePushDiagnostic() async -> String {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard settings.authorizationStatus == .authorized ||
                settings.authorizationStatus == .provisional else {
            return "❌ 尚未取得通知權限，請先開啟通知"
        }
        guard let token = lastDeviceToken else {
            UIApplication.shared.registerForRemoteNotifications()
            return "⏳ 已向 APNs 要求 device token。幾秒後 token 到了會自動上傳，請再按一次查看結果。\n（實機才拿得到 token，Simulator 不行）"
        }
        switch await performUpload(token: token) {
        case .active(let id):
            // 註冊沒問題 → 直接請後端透過 SNS 發一則真的測試推播,完成端到端驗證
            struct TestPushResult: Codable { let sent: Int }
            if let result: TestPushResult = try? await APIClient.shared.request(
                "/push-devices/test", method: "POST"
            ) {
                if result.sent > 0 {
                    return "✅ active — 已請 SNS 發送測試推播到 \(result.sent) 台裝置，幾秒內應收到通知（id: \(id)）"
                }
                return "🟡 active — 註冊正常，但測試推播發送了 0 台（endpoint 可能已失效，請重開通知權限再試）"
            }
            return "✅ active — SNS 已就緒（id: \(id)）；測試推播端點尚未部署，請更新後端後再試"
        case .pending(let id):
            return "🟡 pending_sns_configuration — token 已存後端 RDS，等待 SNS 設定（id: \(id)）"
        case .unknown(let status):
            return "⚠️ 後端回了未知狀態：\(status)"
        case .failed(let message):
            return "❌ 上傳失敗：\(message)\n（後端 /push-devices 未上線會是 404；未登入會是 401）"
        }
    }

    // MARK: - Internal

    private enum UploadOutcome {
        case active(id: String)
        case pending(id: String)
        case unknown(status: String)
        case failed(message: String)
    }

    private func uploadIfPossible() async {
        guard let token = lastDeviceToken else { return }

        // 未登入時後端無法辨識 user_id，先保留 token，等登入後補傳。
        guard KeychainStore.shared.sessionToken != nil ||
                !AppPreferenceStore.shared.currentUserId.isEmpty else { return }

        switch await performUpload(token: token) {
        case .active(let id):
            print("✅ Push: 裝置已完成 SNS 推播註冊 (id: \(id))")
        case .pending(let id):
            // token 已成功存入 RDS，這不是 iOS 錯誤，不要進入重試迴圈。
            print("✅ Push: token 已存後端，等待 SNS 設定 (id: \(id))")
        case .unknown(let status):
            print("⚠️ Push: 未知的註冊狀態 \(status)")
        case .failed(let message):
            // 401（尚未登入 / token 過期）或後端尚未實作 /push-devices 都會走這裡。
            // 保留 lastDeviceToken，下次啟動或登入後再重試，不在此無限重試。
            print("⚠️ Push: 上傳 device token 失敗，稍後重試：\(message)")
        }
    }

    /// 實際打 POST /push-devices，把結果轉成 outcome。成功時記住 device id。
    private func performUpload(token: String) async -> UploadOutcome {
        do {
            let body = PushDeviceRegisterRequest(deviceToken: token, environment: environment)
            let result: PushDeviceRegistration = try await APIClient.shared.requestBody(
                "/push-devices",
                method: "POST",
                body: body
            )
            registeredDeviceId = result.id
            switch result.registrationStatus {
            case "active":
                return .active(id: result.id)
            case "pending_sns_configuration":
                return .pending(id: result.id)
            default:
                return .unknown(status: result.registrationStatus)
            }
        } catch {
            return .failed(message: error.localizedDescription)
        }
    }
}
