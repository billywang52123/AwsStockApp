import SwiftUI

enum AppRoute {
    case splash
    case login
    case onboarding
    case styleQuiz
    case portfolioInput
    case recommendation(symbols: [String])
    case mainApp
}

struct AppRouterView: View {
    @State private var currentRoute: AppRoute = .splash
    @ObservedObject private var container = DependencyContainer.shared
    
    var body: some View {
        ZStack {
            switch currentRoute {
            case .splash:
                SplashView {
                    if AppPreferenceStore.shared.isLoggedIn {
                        if AppPreferenceStore.shared.isOnboardingCompleted {
                            currentRoute = .mainApp
                        } else {
                            currentRoute = .onboarding
                        }
                    } else {
                        currentRoute = .login
                    }
                }
                
            case .login:
                LoginView {
                    Task { await routeAfterLogin() }
                }
                
            case .onboarding:
                OnboardingView {
                    currentRoute = .styleQuiz
                }

            // 18a 新 onboarding 第 1 步:風格測驗(可跳過),取代舊 1a-03 情境選擇;
            // 跳過或完成都 crossfade 進 2/3 持股輸入
            case .styleQuiz:
                OnboardingStyleQuizView {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        currentRoute = .portfolioInput
                    }
                }
                
            case .portfolioInput:
                PortfolioInputView { symbols in
                    currentRoute = .recommendation(symbols: symbols)
                }
                
            case .recommendation(let symbols):
                StockRecommendationView(initialSymbols: symbols) {
                    currentRoute = .mainApp
                }
                
            case .mainApp:
                AppTabView()
                    .environmentObject(container)
            }
        }
        .task {
            // Upgrades from token-less builds: silently obtain a session token
            await AuthService.shared.ensureSessionToken()
        }
        // 設定頁登出 → 回登入頁
        .onReceive(NotificationCenter.default.publisher(for: .authSessionDidEnd)) { _ in
            currentRoute = .login
        }
    }

    /// 登入成功後的路由:本機旗標沒有時,再問雲端有沒有這個帳號的資料
    /// (換機/重裝的老用戶),有就直接進主畫面,不再重問初次問題。
    private func routeAfterLogin() async {
        if AppPreferenceStore.shared.isOnboardingCompleted {
            currentRoute = .mainApp
            return
        }
        if await AuthService.shared.hasExistingRemoteData() {
            AppPreferenceStore.shared.isOnboardingCompleted = true
            currentRoute = .mainApp
            return
        }
        currentRoute = .onboarding
    }
}
