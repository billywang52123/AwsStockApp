import SwiftUI

struct AppTabView: View {
    @State private var selectedTab = 0
    @ObservedObject private var achievementCenter = AchievementCenter.shared

    var body: some View {
        TabView(selection: $selectedTab) {
            TodayDashboardView(activeTab: $selectedTab)
                .tabItem {
                    Label("今日", systemImage: "sparkles")
                }
                .tag(0)
            
            CardDrawView()
                .tabItem {
                    Label("抽卡", systemImage: "suit.spade.fill")
                }
                .tag(1)
            
            PortfolioListView()
                .tabItem {
                    Label("持股", systemImage: "briefcase.fill")
                }
                .tag(2)

            PortfolioAnalysisView(activeTab: $selectedTab)
                .tabItem {
                    Label("分析", systemImage: "chart.pie.fill")
                }
                .tag(3)

            ReminderSettingView()
                .tabItem {
                    Label("設定", systemImage: "gearshape.fill")
                }
                .tag(4)
        }
        .tint(AppColor.primary)
        // 成就達成彈窗：後端 evaluate 回傳新解鎖成就時，從任何分頁彈出慶祝視窗
        .sheet(isPresented: Binding(
            get: { !achievementCenter.pendingUnlocks.isEmpty },
            set: { if !$0 { achievementCenter.dismissPopup() } }
        )) {
            AchievementUnlockView(achievements: achievementCenter.pendingUnlocks) {
                achievementCenter.dismissPopup()
            }
        }
        .onAppear {
            // Apply standard UITabBar appearance for clear styling
            let appearance = UITabBarAppearance()
            appearance.configureWithOpaqueBackground()
            UITabBar.appearance().standardAppearance = appearance
            UITabBar.appearance().scrollEdgeAppearance = appearance
        }
    }
}
