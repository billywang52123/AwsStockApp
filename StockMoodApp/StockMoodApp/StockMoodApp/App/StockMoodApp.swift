import SwiftUI
import GoogleSignIn

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
}
