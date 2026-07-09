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

    private enum AddMode: String, CaseIterable {
        case keyword = "代號搜尋"
        case ai = "AI 找股"
    }

    @State private var mode: AddMode = .keyword
    @State private var keyword = ""
    @State private var results: [Stock] = []
    @State private var isSearching = false
    @FocusState private var searchFocused: Bool

    // AI 找股(自然語言條件 → 後端驗證過的名單)
    @State private var aiQuery = ""
    @State private var aiResult: AiScreenResult?
    @State private var isAiSearching = false
    @State private var aiFailed = false
    @State private var addedSymbols: Set<String> = []
    @FocusState private var aiFocused: Bool

    private let container = DependencyContainer.shared
    private let aiExamples = ["高股息", "殖利率 5% 以上", "月配息 ETF", "半導體龍頭"]

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

            modePicker
                .padding(.top, 14)

            switch mode {
            case .keyword: keywordSection
            case .ai: aiSection
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

    // MARK: 模式切換(代號搜尋 / AI 找股)

    private var modePicker: some View {
        HStack(spacing: 8) {
            ForEach(AddMode.allCases, id: \.self) { item in
                Button {
                    HapticManager.shared.triggerImpact(style: .light)
                    withAnimation(.easeOut(duration: 0.15)) { mode = item }
                    if item == .ai { aiFocused = true } else { searchFocused = true }
                } label: {
                    HStack(spacing: 4) {
                        if item == .ai {
                            Image(systemName: "sparkles")
                                .font(.system(size: 11, weight: .bold))
                        }
                        Text(item.rawValue)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(mode == item ? Color.white : AppColor.inkTertiary)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 16)
                    .background(mode == item ? AppColor.primary : AppColor.bgInset)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: 代號搜尋(原有流程)

    private var keywordSection: some View {
        Group {
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
                .padding(.top, 14)
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
        }
    }

    // MARK: AI 找股

    private var aiSection: some View {
        Group {
            HStack(spacing: 8) {
                TextField("描述條件,例如:殖利率 5% 以上的高股息", text: $aiQuery)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .focused($aiFocused)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .onSubmit { Task { await aiScreen() } }
                    .padding(.vertical, 14)
                    .padding(.horizontal, 16)
                    .background(AppColor.bgInset)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(aiFocused ? AppColor.primary : AppColor.bgTrack, lineWidth: 1.5)
                    )

                Button {
                    HapticManager.shared.triggerImpact(style: .light)
                    Task { await aiScreen() }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(aiQuery.trimmingCharacters(in: .whitespaces).isEmpty ? AppColor.inkFaint : AppColor.primary)
                }
                .buttonStyle(PressScaleButtonStyle())
                .disabled(aiQuery.trimmingCharacters(in: .whitespaces).isEmpty || isAiSearching)
            }
            .padding(.top, 14)

            // 範例條件 chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(aiExamples, id: \.self) { example in
                        Button {
                            HapticManager.shared.triggerImpact(style: .light)
                            aiQuery = example
                            Task { await aiScreen() }
                        } label: {
                            Text(example)
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundColor(AppColor.inkSecondary)
                                .padding(.vertical, 6)
                                .padding(.horizontal, 12)
                                .background(AppColor.bgInset)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.top, 10)

            if isAiSearching {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("AI 正在整理符合條件的名單...")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundColor(AppColor.inkTertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
            } else if aiFailed {
                Text("AI 找股暫時失敗了,稍後再試一次")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundColor(AppColor.inkTertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
            } else if let result = aiResult {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 8) {
                        if let note = result.note {
                            Text(note)
                                .font(.system(size: 12, design: .rounded))
                                .foregroundColor(AppColor.inkTertiary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        ForEach(result.items) { item in
                            aiResultRow(item)
                        }
                        if !result.items.isEmpty {
                            Text("名單由 AI 依你的條件整理,僅供參考")
                                .font(.system(size: 11, design: .rounded))
                                .foregroundColor(AppColor.inkFaint)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 8)
                        }
                    }
                    .padding(.top, 14)
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 28))
                        .foregroundColor(AppColor.primary.opacity(0.5))
                    Text("告訴 AI 你想找什麼樣的股票,\n它會列出名單讓你挑著加入。")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundColor(AppColor.inkTertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
            }
        }
    }

    private func aiResultRow(_ item: AiScreenItem) -> some View {
        let added = addedSymbols.contains(item.symbol)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                IndustryAvatar(name: item.name, industry: item.industry ?? "其他")
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.name)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(AppColor.inkPrimary)
                    Text(item.industry.map { "\(item.symbol) · \($0)" } ?? item.symbol)
                        .font(.system(size: 11, design: .rounded))
                        .foregroundColor(AppColor.inkQuaternary)
                }
                Spacer()
                if let close = item.closePrice {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(close.formatted(.number.precision(.fractionLength(0...2))))
                            .font(.system(size: 14, weight: .heavy, design: .rounded))
                            .monospacedDigit()
                            .foregroundColor(AppColor.inkPrimary)
                        if let change = item.changePercent {
                            Text(StockFormat.signedPercent(change))
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .foregroundColor(change > 0 ? AppColor.upText : (change < 0 ? AppColor.downText : AppColor.neutralText))
                        }
                    }
                }
                Button {
                    guard !added else { return }
                    HapticManager.shared.triggerImpact(style: .light)
                    Task {
                        await viewModel.addStock(symbol: item.symbol)
                        addedSymbols.insert(item.symbol)
                    }
                } label: {
                    Image(systemName: added ? "checkmark.circle.fill" : "plus.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(added ? AppColor.upText : AppColor.primary)
                }
                .buttonStyle(.plain)
                .disabled(added)
            }

            Text(item.reason)
                .font(.system(size: 12, design: .rounded))
                .foregroundColor(AppColor.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(AppColor.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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

    private func aiScreen() async {
        let query = aiQuery.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty, !isAiSearching else { return }
        aiFocused = false
        isAiSearching = true
        aiFailed = false
        do {
            aiResult = try await container.stockService.aiScreenStocks(query: query)
        } catch {
            aiFailed = true
            print("AI screen stocks failed: \(error)")
        }
        isAiSearching = false
    }
}
