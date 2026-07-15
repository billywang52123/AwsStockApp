import SwiftUI
import GoogleSignIn
import UserNotifications

@main
struct StockMoodApp: App {

    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ZStack {
                AppRouterView()

                // 10c 背景遮罩:進 App Switcher / 背景時蓋住內容,快照不外洩(永遠開啟)
                if scenePhase != .active {
                    SnapshotShield()
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
            .animation(.easeOut(duration: 0.2), value: scenePhase == .active)
            // Light Mode MVP：色票皆為固定淺色（見 docs/uiux/README.md），
            // 系統深色模式會把原生元件轉黑底造成混色不可讀，故全域鎖定淺色。
            // Dark Mode 需等設計稿的深色 tokens 出來後再開放。
            .preferredColorScheme(.light)
            .onOpenURL { url in
                // Handle Google Sign-In OAuth callback URL
                GIDSignIn.sharedInstance.handle(url)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                // 回背景重新上鎖持股頁(Face ID 鎖開啟時)
                PrivacyManager.shared.handleEnterBackground()
            }
        }
    }
}

// MARK: - AppDelegate
class AppDelegate: NSObject, UIApplicationDelegate {
    
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // 若通知權限已授權，啟動時就向 APNs 註冊，讓 token 保持最新。
        PushDeviceService.shared.registerForRemoteNotificationsIfPermitted()

        // 接收遠端推播(前景顯示 + 點擊處理,如 16e 風格轉變紅點)
        UNUserNotificationCenter.current().delegate = self

        // Configure GoogleSignIn with client ID from GoogleService-Info.plist
        guard let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
              let plist = NSDictionary(contentsOfFile: path),
              let clientId = plist["CLIENT_ID"] as? String else {
            print("⚠️ GoogleService-Info.plist missing or CLIENT_ID not found")
            return true
        }
        let config = GIDConfiguration(clientID: clientId)
        GIDSignIn.sharedInstance.configuration = config
        print("✅ GoogleSignIn configured with clientID: \(clientId)")
        return true
    }
    
    // Handle Google OAuth redirect URL
    func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        return GIDSignIn.sharedInstance.handle(url)
    }

    // MARK: - Remote Push (APNs)

    /// Apple 成功回傳 APNs device token。轉成 hex 字串後交給後端註冊。
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        print("📶 APNs device token: \(token)")
        PushDeviceService.shared.handleNewToken(token)
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("⚠️ APNs 註冊失敗：\(error.localizedDescription)")
    }
}

// MARK: - 通知接收(前景顯示 + 點擊路由)
extension AppDelegate: UNUserNotificationCenterDelegate {

    private func handlePushPayload(_ userInfo: [AnyHashable: Any]) {
        // 後端 SNS payload 把自訂欄位放在 aps 同層(見 sns_push_service.publish)
        guard let type = userInfo["type"] as? String else { return }
        if type == "style_shift" {
            Task { @MainActor in
                StyleShiftCenter.shared.flagFromPush()
            }
        }
    }

    /// App 在前景時也顯示橫幅,並同步紅點狀態。
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        handlePushPayload(notification.request.content.userInfo)
        completionHandler([.banner, .sound])
    }

    /// 使用者點了通知(背景/關閉狀態進來)。
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        handlePushPayload(response.notification.request.content.userInfo)
        completionHandler()
    }
}
