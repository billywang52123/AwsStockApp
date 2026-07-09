import SwiftUI

struct StockRecommendationView: View {
    @StateObject private var viewModel = StockRecommendationViewModel()
    let initialSymbols: [String]
    let onCompletion: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("為您推薦關注股票")
                .font(.system(.title2, design: .rounded))
                .fontWeight(.bold)
                .foregroundColor(AppColor.textPrimary)
                .padding(.horizontal, 24)
                .padding(.top, 40)
            
            Text("根據您的持股，我們為您挑選了同類型或上下游關聯度高的熱門股。您可以一鍵加入觀察。")
                .font(.system(.subheadline, design: .rounded))
                .foregroundColor(AppColor.textSecondary)
                .padding(.horizontal, 24)
            
            if viewModel.isLoading {
                Spacer()
                ProgressView()
                    .scaleEffect(1.2)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else if viewModel.recommendations.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "hand.thumbsup")
                        .font(.system(size: 40))
                        .foregroundColor(AppColor.textSecondary.opacity(0.5))
                    Text("暫無合適的推薦項目")
                        .font(.system(.headline, design: .rounded))
                        .foregroundColor(AppColor.textSecondary)
                }
                .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 16) {
                        ForEach(Array(viewModel.recommendations.enumerated()), id: \.element.id) { index, stock in
                            RecommendationCard(stock: stock, index: index) {
                                Task {
                                    await viewModel.addRecommendation(stock)
                                }
                            }
                        }

                        // 11g 圖例:星標語意說明
                        if viewModel.recommendations.contains(where: { $0.inWatchlist }) {
                            HStack(spacing: 5) {
                                Image(systemName: "star.fill")
                                    .font(.system(size: 11))
                                    .foregroundColor(AppColor.watchStarIcon)
                                Text("有星星代表這檔已在你的觀察清單裡")
                                    .font(.system(size: 11, design: .rounded))
                                    .foregroundColor(AppColor.inkFaint)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 4)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 8)
                }
            }
            
            Spacer()
            
            VStack(spacing: 16) {
                AppButton(title: "進入我的情緒雷達", icon: "sparkles") {
                    onCompletion()
                }
                
                Button(action: {
                    onCompletion()
                }) {
                    Text("略過此步")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundColor(AppColor.textSecondary)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .background(AppColor.background.edgesIgnoringSafeArea(.all))
        .onAppear {
            Task {
                await viewModel.loadRecommendations(for: initialSymbols)
            }
        }
    }
}

// MARK: - 11g · 推薦卡(已在觀察清單 → amber 描邊 + 星形徽章 + 狀態 pill)
struct RecommendationCard: View {
    let stock: RecommendedStock
    let index: Int
    let onAdd: () -> Void

    @State private var starShown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(stock.name)
                        .font(.system(.body, design: .rounded))
                        .fontWeight(.bold)
                        .foregroundColor(AppColor.textPrimary)

                    if let ind = stock.industry {
                        Text(ind)
                            .font(.system(.caption2, design: .rounded))
                            .fontWeight(.bold)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(AppColor.primary.opacity(0.1))
                            .foregroundColor(AppColor.primary)
                            .cornerRadius(6)
                    }
                }
                Text(stock.symbol)
                    .font(.system(.caption, design: .rounded))
                    .foregroundColor(AppColor.textSecondary)
            }

            Spacer()

            if stock.inWatchlist {
                // 狀態 pill:「在觀察清單」而非「已持有」,不可再點加入
                Text("在「\(stock.watchlistName ?? "觀察清單")」中")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(AppColor.watchStatusPillText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(AppColor.watchStatusPillBg)
                    .clipShape(Capsule())
            } else {
                Button(action: onAdd) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                        Text("加入")
                    }
                    .font(.system(.subheadline, design: .rounded))
                    .fontWeight(.bold)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(AppColor.primary)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
            }
        }
        .padding(16)
        .background(AppColor.cardBackground)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(stock.inWatchlist ? AppColor.watchScoreBorder : Color.clear, lineWidth: 1.5)
        )
        .overlay(alignment: .topTrailing) {
            if stock.inWatchlist {
                ZStack {
                    Circle()
                        .fill(AppColor.watchStarBadgeBg)
                        .frame(width: 26, height: 26)
                    Image(systemName: "star.fill")
                        .font(.system(size: 14))
                        .foregroundColor(AppColor.watchStarIcon)
                }
                .padding(.top, 12)
                .padding(.trailing, 12)
                .scaleEffect(starShown || reduceMotion ? 1 : 0.6)
                .opacity(starShown || reduceMotion ? 1 : 0)
            }
        }
        .shadow(color: Color.black.opacity(0.02), radius: 6, x: 0, y: 3)
        .onAppear {
            // 星標進場:scale 0.6→1 + fade,spring,依卡片順序 stagger 60ms
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7).delay(Double(index) * 0.06)) {
                starShown = true
            }
        }
    }
}
