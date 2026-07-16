import SwiftUI

struct AppTabView: View {
    @State private var selectedTab = 0
    @ObservedObject private var achievementCenter = AchievementCenter.shared
    @ObservedObject private var styleShiftCenter = StyleShiftCenter.shared

    var body: some View {
        TabView(selection: $selectedTab) {
            TodayDashboardView(activeTab: $selectedTab)
                .tabItem {
                    Label("今日", systemImage: "sparkles")
                }
                .tag(0)
            
            // 每日抽卡包 + AI 信任系統(spec 06,取代御神籤)
            TodayPackView()
                .tabItem {
                    Label("抽卡", systemImage: "square.stack.fill")
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
                // 16e 風格轉變未讀 → 設定 tab 紅點
                .badge(styleShiftCenter.hasUnseenShift ? 1 : 0)
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
        .task {
            // App 啟動先請後端預熱 /insights 快取(換日後第一次開 App 就開始算),
            // fire-and-forget,失敗無妨。
            let _: String? = try? await APIClient.shared.request("/insights/prewarm", method: "POST")
            // 接著把「分析」「持股」兩個分頁整頁預載進共用 ViewModel,
            // 使用者點進分頁時資料已在記憶體,不再轉圈;
            // 分析頁的 /insights 會與上面的預熱在後端 single-flight 合流,不會重算。
            async let analysisPreload: Void = AnalysisViewModel.shared.load()
            async let portfolioPreload: Void = PortfolioListViewModel.shared.loadPortfolio()
            _ = await (analysisPreload, portfolioPreload)
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
