import SwiftUI

// MARK: - 11c · 觀察清單頁 WatchlistHomeView
/// 嵌在持股頁內(11a 切到某份觀察清單時顯示),強調「還沒買」與 AI 評分,
/// 不顯示市值/損益。
struct WatchlistHomeView: View {
    @ObservedObject var viewModel: WatchlistViewModel
    let onConvert: (WatchStock) -> Void

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                if let detail = viewModel.detail {
                    Text("\(detail.stockCount) 檔觀察中 · AI 先幫你盯著")
                        .font(.system(size: 13, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(AppColor.inkTertiary)
                        .padding(.top, 8)

                    if detail.items.isEmpty {
                        emptyState
                            .padding(.top, 48)
                    } else {
                        scoreCard(detail)
                            .padding(.top, 14)
                            .entrance(index: 0)

                        VStack(spacing: 11) {
                            ForEach(Array(detail.items.enumerated()), id: \.element.id) { index, stock in
                                WatchlistRow(stock: stock) {
                                    onConvert(stock)
                                }
                                .entrance(index: index + 1, stagger: 0.06)
                            }
                        }
                        .padding(.top, 12)

                        Text("觀察清單不計入市值與損益,評分僅供參考")
                            .font(.system(size: 11, design: .rounded))
                            .foregroundColor(AppColor.inkFaint)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 16)
                    }
                } else if viewModel.isLoadingDetail {
                    ProgressView("正在整理觀察清單...")
                        .frame(maxWidth: .infinity)
                        .padding(.top, 80)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
        .refreshable { await viewModel.refreshSelected() }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "star")
                .font(.system(size: 40))
                .foregroundColor(AppColor.watchStarIcon.opacity(0.6))
            Text("這份清單還是空的")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundColor(AppColor.inkPrimary)
            Text("點右上角 + 加入想追蹤的股票,AI 會幫你先看著。")
                .font(.system(size: 13, design: .rounded))
                .foregroundColor(AppColor.inkTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    // 清單平均分數卡(amber 系)
    private func scoreCard(_ detail: WatchlistDetail) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("清單平均 AI 評分")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(AppColor.amberText)
                CountUpText(value: Double(detail.averageScore), format: { String(format: "%.0f", $0) }, duration: 0.3)
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                    .foregroundColor(AppColor.watchScoreStrong)
            }
            Spacer()
            HStack(spacing: 6) {
                outlookCountPill(.bullish, count: detail.bullishCount)
                outlookCountPill(.neutral, count: detail.neutralCount)
                outlookCountPill(.caution, count: detail.cautionCount)
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 17)
        .background(AppColor.watchScoreBg)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(AppColor.watchScoreBorder, lineWidth: 1.5)
        )
    }

    private func outlookCountPill(_ outlook: Outlook, count: Int) -> some View {
        Text("\(outlook.label) \(count)")
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundColor(outlook.textColor)
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(outlook.bgColor)
            .clipShape(Capsule())
    }
}

// MARK: - 觀察股列 WatchlistRow(兩層:個股資訊 + 評分/轉入)

struct WatchlistRow: View {
    let stock: WatchStock
    let onConvert: () -> Void

    private var changeColor: Color {
        if stock.changePercent > 0 { return AppColor.upText }
        if stock.changePercent < 0 { return AppColor.downText }
        return AppColor.neutralText
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 第一層:同持股列,但無損益欄(未持有)
            HStack(spacing: 10) {
                IndustryAvatar(name: stock.name, industry: stock.industry)
                VStack(alignment: .leading, spacing: 1) {
                    Text(stock.name)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(AppColor.inkPrimary)
                    Text("\(stock.symbol) · \(stock.industry)")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundColor(AppColor.inkQuaternary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    if let close = stock.closePrice {
                        Text(close.formatted(.number.precision(.fractionLength(0...2))))
                            .font(.system(size: 15, weight: .heavy, design: .rounded))
                            .monospacedDigit()
                            .foregroundColor(AppColor.inkPrimary)
                    } else {
                        Text("--")
                            .font(.system(size: 15, weight: .heavy, design: .rounded))
                            .foregroundColor(AppColor.inkQuaternary)
                    }
                    Text(StockFormat.signedPercent(stock.changePercent))
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(changeColor)
                }
            }

            // 第二層:AI 評分 pill + OutlookBadge + 轉入庫存
            HStack(spacing: 8) {
                Text("AI 評分 \(stock.aiScore)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(AppColor.watchScoreStrong)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 10)
                    .background(AppColor.watchScoreBg)
                    .clipShape(Capsule())

                OutlookBadge(outlook: stock.outlook)

                Spacer()

                Button(action: {
                    HapticManager.shared.triggerImpact(style: .light)
                    onConvert()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.right.circle")
                            .font(.system(size: 12, weight: .semibold))
                        Text("轉入庫存")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(AppColor.primary)
                    .padding(.vertical, 5)
                    .padding(.horizontal, 12)
                    .overlay(Capsule().strokeBorder(AppColor.primary, lineWidth: 1.5))
                }
                .buttonStyle(PressScaleButtonStyle())
            }
        }
        .padding(.vertical, 15)
        .padding(.horizontal, 17)
        .background(AppColor.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: Color(hex: "786446").opacity(0.06), radius: 9, x: 0, y: 6)
    }
}

// MARK: - 加入觀察股(11c 右上 + 按鈕 → 股票搜尋)

struct AddWatchStockSheet: View {
    @ObservedObject var viewModel: WatchlistViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var keyword = ""
    @State private var results: [Stock] = []
    @State private var isSearching = false
    @FocusState private var searchFocused: Bool

    private let container = DependencyContainer.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Capsule()
                .fill(AppColor.bgTrack)
                .frame(width: 40, height: 5)
                .frame(maxWidth: .infinity)
                .padding(.top, 14)

            Text("加入觀察股")
                .font(.system(size: 21, weight: .heavy, design: .rounded))
                .foregroundColor(AppColor.inkPrimary)
                .padding(.top, 18)
            if let list = viewModel.selectedList {
                Text("加入「\(list.name)」,AI 會開始幫你追蹤")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundColor(AppColor.inkTertiary)
                    .padding(.top, 4)
            }

            TextField("搜尋代號或名稱,例如 2330", text: $keyword)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .focused($searchFocused)
                .autocorrectionDisabled()
                .padding(.vertical, 14)
                .padding(.horizontal, 16)
                .background(AppColor.bgInset)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(searchFocused ? AppColor.primary : AppColor.bgTrack, lineWidth: 1.5)
                )
                .padding(.top, 16)
                .onChange(of: keyword) { _, newValue in
                    Task { await search(newValue) }
                }

            if isSearching {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.top, 32)
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 8) {
                        ForEach(results) { stock in
                            Button {
                                HapticManager.shared.triggerImpact(style: .light)
                                Task {
                                    await viewModel.addStock(symbol: stock.symbol)
                                    dismiss()
                                }
                            } label: {
                                HStack(spacing: 10) {
                                    IndustryAvatar(name: stock.name, industry: stock.industry ?? "其他")
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(stock.name)
                                            .font(.system(size: 15, weight: .bold, design: .rounded))
                                            .foregroundColor(AppColor.inkPrimary)
                                        Text(stock.symbol)
                                            .font(.system(size: 11, design: .rounded))
                                            .foregroundColor(AppColor.inkQuaternary)
                                    }
                                    Spacer()
                                    Image(systemName: "plus.circle.fill")
                                        .font(.system(size: 22))
                                        .foregroundColor(AppColor.primary)
                                }
                                .padding(.vertical, 12)
                                .padding(.horizontal, 14)
                                .background(AppColor.cardBackground)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, 14)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
        .background(AppColor.background)
        .presentationDetents([.medium, .large])
        .onAppear {
            searchFocused = true
            Task { await search("") }
        }
    }

    private func search(_ text: String) async {
        isSearching = results.isEmpty
        do {
            results = try await container.stockService.searchStocks(keyword: text)
        } catch {
            print("Search stocks failed: \(error)")
        }
        isSearching = false
    }
}
