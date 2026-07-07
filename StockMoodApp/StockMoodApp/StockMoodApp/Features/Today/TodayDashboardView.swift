import SwiftUI

struct TodayDashboardView: View {
    @StateObject private var viewModel = TodayDashboardViewModel()
    @Binding var activeTab: Int // binding to switch tabs programmatically
    @State private var showExplanationDetail = false
    
    var body: some View {
        NavigationView {
            ZStack {
                AppColor.background
                    .edgesIgnoringSafeArea(.all)
                
                if viewModel.isLoading {
                    ProgressView("正在分析持股波動與市場情緒...")
                        .scaleEffect(1.1)
                } else if viewModel.hasError {
                    ErrorStateView(message: viewModel.errorMessage) {
                        Task { await viewModel.loadData() }
                    }
                } else if !viewModel.hasPortfolioItems {
                    EmptyStateView(
                        title: "您還沒有加入持股",
                        message: "先加入 1 檔您關心的股票，我們會幫您整理今天的波動原因與情緒分析。",
                        buttonTitle: "新增持股"
                    ) {
                        activeTab = 2 // Switch to Portfolio Tab
                    }
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 24) {
                            
                            // Anxiety Dashboard Header Card
                            AppCard {
                                VStack(spacing: 16) {
                                    Text("今日持股焦慮度")
                                        .font(.system(.headline, design: .rounded))
                                        .foregroundColor(AppColor.textSecondary)
                                    
                                    AnxietyScoreRing(score: viewModel.anxietyScore, level: viewModel.anxietyLevel)
                                        .padding(.vertical, 8)
                                    
                                    Text(viewModel.mainReason)
                                        .font(.system(.subheadline, design: .rounded))
                                        .fontWeight(.bold)
                                        .foregroundColor(AppColor.textPrimary)
                                        .multilineTextAlignment(.center)
                                    
                                    Text(viewModel.anxietyMessage)
                                        .font(.system(.footnote, design: .rounded))
                                        .foregroundColor(AppColor.textSecondary)
                                        .multilineTextAlignment(.center)
                                        .lineSpacing(4)
                                        .padding(.horizontal, 8)
                                }
                            }
                            
                            // Market Comparison Component
                            if let compare = viewModel.compareResult {
                                MarketCompareCard(result: compare)
                            }
                            
                            // Action Section
                            VStack(spacing: 14) {
                                NavigationLink(destination: DailyExplanationView(), isActive: $showExplanationDetail) {
                                    EmptyView()
                                }
                                
                                AppButton(title: "查看今天白話原因", icon: "doc.text.magnifyingglass") {
                                    showExplanationDetail = true
                                }
                                
                                AppButton(title: "抽今日情緒陪伴卡", icon: "suit.spade.fill", backgroundColor: AppColor.secondary, textColor: AppColor.textPrimary) {
                                    activeTab = 1 // Switch to Draw Tab
                                }
                            }
                            
                            DisclaimerView()
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                    }
                }
            }
            .navigationTitle("今日情緒雷達")
            .navigationBarTitleDisplayMode(.large)
            .onAppear {
                Task {
                    await viewModel.loadData()
                    // Re-check achievement conditions against today's snapshot
                    AchievementCenter.shared.evaluate()
                }
            }
        }
    }
}
