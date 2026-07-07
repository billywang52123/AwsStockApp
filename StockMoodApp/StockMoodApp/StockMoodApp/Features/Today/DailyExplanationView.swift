import SwiftUI

struct DailyExplanationView: View {
    @StateObject private var viewModel = DailyExplanationViewModel()
    
    var body: some View {
        ZStack {
            AppColor.background
                .edgesIgnoringSafeArea(.all)
            
            if viewModel.isLoading {
                ProgressView("正在生成今日市場白話分析...")
            } else if let summary = viewModel.summary {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 24) {
                        
                        // Summary Title & Explanation Block
                        VStack(alignment: .leading, spacing: 12) {
                            Text(summary.title)
                                .font(.system(.title3, design: .rounded))
                                .fontWeight(.bold)
                                .foregroundColor(AppColor.textPrimary)
                            
                            Text(summary.summary)
                                .font(.system(.body, design: .rounded))
                                .foregroundColor(AppColor.textPrimary)
                                .lineSpacing(6)
                        }
                        .padding(20)
                        .background(AppColor.cardBackground)
                        .cornerRadius(20)
                        .shadow(color: Color.black.opacity(0.01), radius: 8, x: 0, y: 4)
                        
                        // Explanation block
                        ExplanationBlock(
                            title: "新手翻譯官",
                            content: summary.explanation,
                            systemIcon: "bubble.left.and.bubble.right.fill"
                        )
                        
                        // Portfolio Impact Items
                        VStack(alignment: .leading, spacing: 16) {
                            Text("持股波動原因拆解")
                                .font(.system(.headline, design: .rounded))
                                .foregroundColor(AppColor.textPrimary)
                                .padding(.horizontal, 4)
                            
                            ForEach(summary.portfolioImpactItems) { item in
                                let isUp = item.changePercent >= 0
                                
                                AppCard {
                                    VStack(alignment: .leading, spacing: 10) {
                                        HStack {
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(item.name)
                                                    .font(.system(.body, design: .rounded))
                                                    .fontWeight(.bold)
                                                    .foregroundColor(AppColor.textPrimary)
                                                Text(item.symbol)
                                                    .font(.system(.caption, design: .rounded))
                                                    .foregroundColor(AppColor.textSecondary)
                                            }
                                            
                                            Spacer()
                                            
                                            HStack(spacing: 8) {
                                                Text(String(format: "%@%.1f%%", isUp ? "+" : "", item.changePercent))
                                                    .font(.system(.headline, design: .rounded))
                                                    .foregroundColor(isUp ? AppColor.primary : AppColor.danger)
                                                
                                                // Impact Badge
                                                Text(item.impactLevel.rawValue == "HIGH" ? "影響高" : item.impactLevel.rawValue == "MEDIUM" ? "影響中" : "影響低")
                                                    .font(.system(.caption2, design: .rounded))
                                                    .fontWeight(.bold)
                                                    .padding(.horizontal, 8)
                                                    .padding(.vertical, 4)
                                                    .background(item.impactLevel.rawValue == "HIGH" ? AppColor.danger.opacity(0.1) : AppColor.textSecondary.opacity(0.1))
                                                    .foregroundColor(item.impactLevel.rawValue == "HIGH" ? AppColor.danger : AppColor.textSecondary)
                                                    .cornerRadius(6)
                                            }
                                        }
                                        
                                        Divider()
                                            .padding(.vertical, 4)
                                        
                                        Text(item.reason)
                                            .font(.system(.subheadline, design: .rounded))
                                            .foregroundColor(AppColor.textSecondary)
                                            .lineSpacing(4)
                                    }
                                }
                            }
                        }
                        
                        DisclaimerView()
                            .frame(maxWidth: .infinity)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
            } else {
                Text("無法取得今日情緒分析")
                    .foregroundColor(AppColor.textSecondary)
            }
        }
        .navigationTitle("情緒分析報告")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            Task {
                await viewModel.loadSummary()
            }
        }
    }
}
