import SwiftUI

/// 8e 個股觀點詳情:AI 綜合觀點卡(多空溫度計)+ 訊號卡 + 白話總結。
struct StockInsightDetailView: View {
    let symbol: String
    let name: String
    @StateObject private var viewModel = StockInsightDetailViewModel()

    var body: some View {
        ZStack {
            AppColor.background.ignoresSafeArea()

            if viewModel.isLoading {
                ProgressView("AI 正在整理觀點...")
            } else if viewModel.hasError {
                ErrorStateView(message: viewModel.errorMessage) {
                    Task { await viewModel.load(symbol: symbol) }
                }
            } else if let detail = viewModel.detail {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        // AI 綜合觀點卡
                        overviewCard(detail)
                            .padding(.top, 16)
                            .entrance(index: 0, stagger: 0.09)

                        // 訊號區標題
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("為什麼這樣看？")
                                .font(.system(size: 14, weight: .heavy, design: .rounded))
                                .foregroundColor(AppColor.inkPrimary)
                            Text("來自近期價格與大盤資料")
                                .font(.system(size: 12, design: .rounded))
                                .foregroundColor(AppColor.inkQuaternary)
                        }
                        .padding(.top, 16)
                        .entrance(index: 1, stagger: 0.09)

                        // 新聞/訊號卡
                        VStack(spacing: 10) {
                            ForEach(Array(detail.signals.enumerated()), id: \.element.id) { index, signal in
                                NewsSignalCard(signal: signal)
                                    .entrance(index: index + 2, stagger: 0.09)
                            }
                        }
                        .padding(.top, 10)

                        // 白話總結(最後進場)
                        PlainSummaryBlock(content: detail.plainSummary)
                            .padding(.top, 12)
                            .entrance(index: detail.signals.count + 2, stagger: 0.09)

                        DisclaimerBlock(text: "AI 觀點僅供參考，不構成投資建議")
                            .padding(.top, 16)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 40)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(name)
                        .font(.system(size: 20, weight: .heavy, design: .rounded))
                        .foregroundColor(AppColor.inkPrimary)
                    Text(symbol)
                        .font(.system(size: 13, design: .rounded))
                        .foregroundColor(AppColor.inkQuaternary)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load(symbol: symbol) }
    }

    private func overviewCard(_ detail: StockInsightDetail) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("AI 綜合觀點")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(AppColor.inkTertiary)
                Spacer()
                Text(detail.stanceLabel)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(detail.outlook.textColor)
                    .padding(.vertical, 5)
                    .padding(.horizontal, 13)
                    .background(detail.outlook.bgColor)
                    .clipShape(Capsule())
            }

            Text(detail.summary)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundColor(AppColor.inkPrimary)
                .lineSpacing(6)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)

            SentimentMeter(score: detail.outlookScore)
                .padding(.top, 18)
        }
        .padding(20)
        .background(AppColor.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: Color(hex: "786446").opacity(0.08), radius: 13, x: 0, y: 10)
    }
}
