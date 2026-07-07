import SwiftUI

enum AppRoute {
    case splash
    case login
    case onboarding
    case scenario
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
                    if AppPreferenceStore.shared.isOnboardingCompleted {
                        currentRoute = .mainApp
                    } else {
                        currentRoute = .onboarding
                    }
                }
                
            case .onboarding:
                OnboardingView {
                    currentRoute = .scenario
                }
                
            case .scenario:
                UserScenarioView {
                    currentRoute = .portfolioInput
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
    }
}
