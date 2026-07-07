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
                        ForEach(viewModel.recommendations) { stock in
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
                                
                                Button(action: {
                                    Task {
                                        await viewModel.addRecommendation(stock)
                                    }
                                }) {
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
                            .padding(16)
                            .background(AppColor.cardBackground)
                            .cornerRadius(16)
                            .shadow(color: Color.black.opacity(0.02), radius: 6, x: 0, y: 3)
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
