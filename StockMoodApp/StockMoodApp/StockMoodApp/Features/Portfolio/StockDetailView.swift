import SwiftUI

/// 17a 統一個股詳情頁:三入口(持股列表 / 庫存分析 / 個股觀點 tab)共用一頁。
/// 上半「今天怎麼了?」(白話翻譯器併入)+ 下半「AI 怎麼看接下來?」(原 8e 併入)。
struct StockDetailView: View {
    /// 入口來源:焦慮影響 chip 只在「從持股列表進入」時顯示(觀察股不計焦慮分數)
    enum Entry {
        case holdings    // 持股列表(預設)
        case analysis    // 庫存分析內文
        case watchlist   // 個股觀點 tab 觀察分頁 / 觀察清單
    }

    let symbol: String
    let name: String
    var entry: Entry = .holdings

    @StateObject private var viewModel: StockDetailViewModel
    @Environment(\.dismiss) var dismiss
    @State private var showAIAnalysisSheet = false
    @State private var selectedSignal: NewsSignal?

    // 持股異動(spec 04 · 9a–9e)
    @State private var holding: Holding?
    @State private var showUpdateIntentSheet = false
    @State private var activeIntent: HoldingUpdateIntent?

    init(symbol: String, name: String, entry: Entry = .holdings) {
        self.symbol = symbol
        self.name = name
        self.entry = entry
        self._viewModel = StateObject(wrappedValue: StockDetailViewModel(symbol: symbol, name: name))
    }

    private var plainSummaryLabel: String {
        entry == .watchlist ? "觀察風向" : "白話總結"
    }

    var body: some View {
        ZStack {
            AppColor.background.ignoresSafeArea()

            if viewModel.isLoading {
                ProgressView("正在整理個股狀態...")
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        // 上半部 · 今天怎麼了?(白話狀態翻譯器併入)
                        todayStatusCard
                            .padding(.top, 16)
                            .entrance(index: 0, stagger: 0.09)

                        // 我的持股卡(9a 入口 + 9e 券商分帳)
                        if let holding {
                            holdingCard(holding)
                                .padding(.top, 12)
                                .entrance(index: 1, stagger: 0.09)
                        }

                        // 分區標題:兩段時間軸不同,同頁分區、文字不合併
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("AI 怎麼看接下來？")
                                .font(.system(size: 14, weight: .heavy, design: .rounded))
                                .foregroundColor(AppColor.inkPrimary)
                            Text("來自近期價格與大盤資料")
                                .font(.system(size: 11, design: .rounded))
                                .foregroundColor(AppColor.inkQuaternary)
                        }
                        .padding(.top, 20)
                        .entrance(index: 2, stagger: 0.09)

                        // 下半部 · AI 綜合觀點卡(原 8e 併入,訊號列內嵌)
                        Group {
                            if let insight = viewModel.insight {
                                aiOutlookCard(insight)
                                    .padding(.top, 10)

                                PlainSummaryBlock(label: plainSummaryLabel, content: insight.plainSummary)
                                    .padding(.top, 12)
                            } else {
                                Text("AI 觀點整理中，稍後再回來看看")
                                    .font(.system(size: 12, design: .rounded))
                                    .foregroundColor(AppColor.inkFaint)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 24)
                            }
                        }
                        .entrance(index: 3, stagger: 0.09)

                        // AI 專家白話分析(個人化:套用投資風格 prompt context)
                        aiAnalysisButton
                            .padding(.top, 16)
                            .entrance(index: 4, stagger: 0.09)

                        // 關聯股票推薦(11g 星標)
                        if !viewModel.recommendations.isEmpty {
                            recommendationSection
                                .padding(.top, 24)
                        }

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
                    Text(subtitleText)
                        .font(.system(size: 13, design: .rounded))
                        .foregroundColor(AppColor.inkQuaternary)
                }
            }
            if entry == .holdings {
                ToolbarItem(placement: .topBarTrailing) {
                    anxietyChip
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            Task {
                await viewModel.loadDetails()
                await reloadHolding()
            }
        }
        .sheet(item: $selectedSignal) { signal in
            SignalExplanationSheet(signal: signal)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showUpdateIntentSheet) {
            if let holding {
                UpdateIntentSheet(holding: holding) { intent in
                    activeIntent = intent
                }
            }
        }
        .sheet(item: $activeIntent) { intent in
            if let holding {
                NavigationView {
                    TradeUpdateView(intent: intent, holding: holding) {
                        Task { await reloadHolding() }
                    }
                }
            }
        }
        .sheet(isPresented: $showAIAnalysisSheet) {
            AIAnalysisSheetView(
                symbol: symbol,
                name: name,
                isFetching: viewModel.isFetchingAIAnalysis,
                text: viewModel.aiAnalysisText,
                errorMessage: viewModel.hasError ? viewModel.errorMessage : nil,
                onRetry: {
                    Task { await viewModel.fetchAIAnalysis() }
                }
            )
        }
    }

    private var subtitleText: String {
        if let industry = viewModel.insight?.industry, !industry.isEmpty {
            return "\(symbol) · \(industry)"
        }
        return symbol
    }

    private func reloadHolding() async {
        holding = try? await DependencyContainer.shared.holdingService.getHolding(symbol: symbol)
    }

    // MARK: - 標題列焦慮影響 chip(僅持股入口)

    private var anxietyChip: some View {
        Text("焦慮影響 \(viewModel.anxietyImpact)")
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundColor(AppColor.amberStrong)
            .padding(.vertical, 4)
            .padding(.horizontal, 10)
            .background(AppColor.amberIconBg)
            .clipShape(Capsule())
    }

    // MARK: - 上半部 · 今天怎麼了?

    private var todayStatusCard: some View {
        let change = viewModel.dailyPrice?.changePercent ?? 0
        let isUp = change >= 0
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("今天怎麼了？")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(AppColor.inkTertiary)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(StockFormat.signedPercent(change))
                        .font(.system(size: 24, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(isUp ? AppColor.upText : AppColor.downText)
                    if let market = viewModel.marketChangePercent {
                        Text("大盤 \(StockFormat.signedPercent(market, digits: 1))")
                            .font(.system(size: 11, design: .rounded))
                            .monospacedDigit()
                            .foregroundColor(AppColor.inkQuaternary)
                    }
                }
            }

            // 原因點列
            VStack(alignment: .leading, spacing: 7) {
                ForEach(Array(viewModel.todayReasons.enumerated()), id: \.offset) { index, reason in
                    HStack(alignment: .top, spacing: 8) {
                        Circle()
                            .fill(index == 0 ? AppColor.warning : AppColor.primary.opacity(0.55))
                            .frame(width: 7, height: 7)
                            .padding(.top, 5)
                        Text(reason)
                            .font(.system(size: 13, design: .rounded))
                            .foregroundColor(AppColor.inkSecondary)
                            .lineSpacing(5)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            // 新手翻譯盒
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 13))
                        .foregroundColor(AppColor.primary)
                    Text("新手翻譯")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(AppColor.primary)
                }
                Text(viewModel.explanation)
                    .font(.system(size: 14, design: .rounded))
                    .foregroundColor(Color(hex: "4A4770"))
                    .lineSpacing(7)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColor.primaryBgTint)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            if let price = viewModel.dailyPrice {
                Text("收盤 \(String(format: "%.2f", price.closePrice)) · 資料日期 \(price.tradeDate.formatted(.dateTime.month().day()))")
                    .font(.system(size: 11, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(AppColor.inkFaint)
            }
        }
        .padding(20)
        .background(AppColor.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: Color(hex: "786446").opacity(0.08), radius: 13, x: 0, y: 10)
    }

    // MARK: - 下半部 · AI 綜合觀點卡(含內嵌訊號列)

    private func aiOutlookCard(_ insight: StockInsightDetail) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("AI 綜合觀點")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(AppColor.inkTertiary)
                Spacer()
                Text(insight.stanceLabel)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(insight.outlook.textColor)
                    .padding(.vertical, 5)
                    .padding(.horizontal, 13)
                    .background(insight.outlook.bgColor)
                    .clipShape(Capsule())
            }

            Text(insight.summary)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(AppColor.inkPrimary)
                .lineSpacing(6)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)

            SentimentMeter(score: insight.outlookScore)
                .padding(.top, 16)

            // 訊號列(內嵌卡內,取代 8e 的獨立新聞卡群)
            VStack(spacing: 0) {
                ForEach(Array(insight.signals.enumerated()), id: \.element.id) { index, signal in
                    Button {
                        selectedSignal = signal
                        HapticManager.shared.triggerImpact(style: .light)
                    } label: {
                        signalRow(signal)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("開啟指標解釋、計算方式與資料來源")

                    if index < insight.signals.count - 1 {
                        Rectangle()
                            .fill(AppColor.bgTrack)
                            .frame(height: 1)
                    }
                }
            }
            .padding(.top, 16)
        }
        .padding(20)
        .background(AppColor.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: Color(hex: "786446").opacity(0.08), radius: 13, x: 0, y: 10)
    }

    /// 17a SignalRow:來源 pill → 一句話 → 方向標籤
    private func signalRow(_ signal: NewsSignal) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(signal.source)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundColor(AppColor.inkTertiary)
                .padding(.vertical, 3)
                .padding(.horizontal, 9)
                .background(AppColor.bgTrack)
                .clipShape(Capsule())

            Text(signal.text)
                .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                .foregroundColor(AppColor.inkPrimary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(signal.directionLabel)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(signal.direction.color)
        }
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }

    // MARK: - AI 專家白話分析按鈕

    private var aiAnalysisButton: some View {
        Button(action: {
            showAIAnalysisSheet = true
            Task {
                await viewModel.fetchAIAnalysis()
            }
        }) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundColor(.white)
                Text("AI 專家白話分析")
                    .fontWeight(.bold)
                    .foregroundColor(.white)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(
                LinearGradient(
                    gradient: Gradient(colors: [Color(hex: "7B7FD4"), Color(hex: "9094E2")]),
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .cornerRadius(14)
            .shadow(color: Color(hex: "7B7FD4").opacity(0.3), radius: 6, x: 0, y: 3)
        }
    }

    // MARK: - 關聯股票推薦(11g)

    private var recommendationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("關聯股票推薦")
                .font(.system(.headline, design: .rounded))
                .foregroundColor(AppColor.textPrimary)
                .padding(.horizontal, 4)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(viewModel.recommendations) { rec in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(rec.name)
                                .font(.system(.subheadline, design: .rounded))
                                .fontWeight(.bold)
                                .foregroundColor(AppColor.textPrimary)
                                .lineLimit(1)

                            Text(rec.symbol)
                                .font(.system(.caption, design: .rounded))
                                .foregroundColor(AppColor.textSecondary)

                            if let industry = rec.industry, !industry.isEmpty {
                                Text(industry)
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                                    .foregroundColor(AppColor.primary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(AppColor.primary.opacity(0.08))
                                    .cornerRadius(6)
                            }
                        }
                        .padding(14)
                        .frame(width: 140, alignment: .leading)
                        .background(AppColor.cardBackground)
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(rec.inWatchlist ? AppColor.watchScoreBorder : Color.clear, lineWidth: 1.5)
                        )
                        .overlay(alignment: .topTrailing) {
                            // 11g 已在觀察清單 → 星形徽章
                            if rec.inWatchlist {
                                ZStack {
                                    Circle()
                                        .fill(AppColor.watchStarBadgeBg)
                                        .frame(width: 20, height: 20)
                                    Image(systemName: "star.fill")
                                        .font(.system(size: 10))
                                        .foregroundColor(AppColor.watchStarIcon)
                                }
                                .padding(6)
                            }
                        }
                        .shadow(color: Color.black.opacity(0.01), radius: 4, x: 0, y: 2)
                    }
                }
            }
        }
    }

    // MARK: - 我的持股卡(合併數字 + 更新入口 + 券商分帳)

    private func holdingCard(_ holding: Holding) -> some View {
        AppCard {
            VStack(spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("我的持股")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundColor(AppColor.textSecondary)

                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                            Text(holding.totalShares.formatted())
                                .font(.system(.title2, design: .rounded).monospacedDigit())
                                .fontWeight(.heavy)
                                .foregroundColor(AppColor.textPrimary)
                            Text("股")
                                .font(.system(.caption, design: .rounded))
                                .foregroundColor(AppColor.textSecondary)
                            if let avg = holding.avgPrice {
                                Text("· 均價 \(avg.trimmedString)")
                                    .font(.system(.caption, design: .rounded).monospacedDigit())
                                    .foregroundColor(AppColor.textSecondary)
                            }
                        }
                        .sensitiveAmount()
                    }

                    Spacer()

                    Button {
                        showUpdateIntentSheet = true
                    } label: {
                        Text("更新持股")
                            .font(.system(.caption, design: .rounded))
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(AppColor.primary)
                            .clipShape(Capsule())
                    }
                }

                if holding.avgPriceIncomplete {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.circle")
                            .font(.caption)
                        Text("有分帳還沒填買價,補填後均價會更準")
                            .font(.system(.caption2, design: .rounded))
                        Spacer()
                    }
                    .foregroundColor(AppColor.amberStrong)
                }

                NavigationLink {
                    BrokerLotsView(symbol: symbol, holding: holding) {
                        Task { await reloadHolding() }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "building.columns")
                            .font(.caption)
                            .foregroundColor(AppColor.primary)
                        Text("\(holding.lots.count) 個券商帳戶")
                            .font(.system(.caption, design: .rounded))
                            .fontWeight(.semibold)
                            .foregroundColor(AppColor.textPrimary)
                        Spacer()
                        Text("查看分帳與異動")
                            .font(.system(.caption2, design: .rounded))
                            .foregroundColor(AppColor.textSecondary)
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundColor(AppColor.textSecondary)
                    }
                    .padding(10)
                    .background(AppColor.bgInset)
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - 訊號詳細解釋(信任系統:欄位/算法/資料日期)

struct SignalExplanationSheet: View {
    let signal: NewsSignal
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    signalOverview

                    explanationSection(
                        icon: "book.closed.fill",
                        title: "這個指標是什麼？",
                        content: signal.explanation
                    )
                    explanationSection(
                        icon: "function",
                        title: "這次怎麼算？",
                        content: signal.calculation,
                        monospaced: true
                    )
                    explanationSection(
                        icon: "arrow.triangle.branch",
                        title: "為什麼得到這個方向？",
                        content: signal.rule
                    )

                    sourceBlock

                    DisclaimerBlock(text: "方向由固定數據門檻判定，不是 AI 憑感覺；內容為現況說明，非投資建議")
                        .padding(.top, 2)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .background(AppColor.background.ignoresSafeArea())
            .navigationTitle("判斷解釋與由來")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private var signalOverview: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(signal.source)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(AppColor.inkTertiary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(AppColor.bgTrack)
                    .clipShape(Capsule())
                Spacer()
                Text(signal.directionLabel)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(signal.direction.color)
            }

            Text(signal.text)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundColor(AppColor.inkPrimary)
                .lineSpacing(6)
        }
        .padding(18)
        .background(AppColor.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func explanationSection(
        icon: String,
        title: String,
        content: String,
        monospaced: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Label(title, systemImage: icon)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(AppColor.inkPrimary)

            Text(content)
                .font(.system(
                    size: monospaced ? 12 : 13,
                    weight: monospaced ? .semibold : .regular,
                    design: monospaced ? .monospaced : .rounded
                ))
                .foregroundColor(AppColor.inkSecondary)
                .lineSpacing(6)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(monospaced ? AppColor.bgInset : AppColor.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var sourceBlock: some View {
        VStack(spacing: 0) {
            sourceRow(label: "資料來源", value: signal.dataSource)
            Divider().padding(.leading, 88)
            sourceRow(label: "資料日期", value: signal.dataDate)
        }
        .background(AppColor.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func sourceRow(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .font(.system(size: 12, design: .rounded))
                .foregroundColor(AppColor.inkTertiary)
                .frame(width: 56, alignment: .leading)
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(AppColor.inkPrimary)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .multilineTextAlignment(.trailing)
        }
        .padding(14)
    }
}

// MARK: - AI Analysis Sheet View
struct AIAnalysisSheetView: View {
    let symbol: String
    let name: String
    let isFetching: Bool
    let text: String?
    var errorMessage: String? = nil
    var onRetry: (() -> Void)? = nil

    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            ZStack {
                AppColor.background
                    .edgesIgnoringSafeArea(.all)

                if isFetching {
                    VStack(spacing: 20) {
                        ProgressView()
                            .scaleEffect(1.3)
                        Text("正在整理對應的 GPT 專家白話分析...")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundColor(AppColor.textSecondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let analysis = text {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            HStack {
                                Image(systemName: "sparkles")
                                    .font(.title2)
                                    .foregroundColor(AppColor.primary)
                                Text("AI 專家今日診斷")
                                    .font(.system(.headline, design: .serif))
                                    .foregroundColor(AppColor.textPrimary)
                            }
                            .padding(.top, 10)

                            // 連線失敗時顯示提示（下方仍呈現離線備用內容）
                            if let error = errorMessage {
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "wifi.exclamationmark")
                                        .foregroundColor(AppColor.warning)
                                    Text(error)
                                        .font(.system(.caption, design: .rounded))
                                        .foregroundColor(AppColor.textSecondary)

                                    Spacer()

                                    if let onRetry = onRetry {
                                        Button("重試") { onRetry() }
                                            .font(.system(.caption, design: .rounded))
                                            .fontWeight(.bold)
                                            .foregroundColor(AppColor.primary)
                                    }
                                }
                                .padding(12)
                                .background(AppColor.warning.opacity(0.1))
                                .cornerRadius(12)
                            }

                            // Parse and render the sections
                            let sections = parseAnalysis(analysis)

                            VStack(spacing: 16) {
                                ForEach(sections, id: \.title) { sec in
                                    VStack(alignment: .leading, spacing: 10) {
                                        HStack(spacing: 8) {
                                            Image(systemName: sec.icon)
                                                .foregroundColor(AppColor.primary)
                                                .font(.headline)
                                            Text(sec.title)
                                                .font(.system(.body, design: .serif))
                                                .fontWeight(.bold)
                                                .foregroundColor(AppColor.textPrimary)
                                        }

                                        Text(sec.content)
                                            .font(.system(.body, design: .rounded))
                                            .foregroundColor(AppColor.textSecondary)
                                            .lineSpacing(6)
                                    }
                                    .padding(16)
                                    .background(Color.white)
                                    .cornerRadius(16)
                                    .shadow(color: Color.black.opacity(0.02), radius: 6, x: 0, y: 3)
                                }
                            }

                            DisclaimerView()
                                .padding(.top, 10)
                        }
                        .padding(24)
                    }
                } else {
                    // 尚未取得內容（例如首次連線失敗且沒有備用文字）
                    VStack(spacing: 16) {
                        Image(systemName: "wifi.exclamationmark")
                            .font(.system(size: 44))
                            .foregroundColor(AppColor.textSecondary.opacity(0.5))
                        Text(errorMessage ?? "暫時無法取得 AI 分析")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundColor(AppColor.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                        if let onRetry = onRetry {
                            Button(action: onRetry) {
                                Text("重新整理")
                                    .font(.system(.subheadline, design: .rounded))
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 24)
                                    .padding(.vertical, 10)
                                    .background(AppColor.primary)
                                    .cornerRadius(12)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("\(name) AI 分析")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("關閉") { dismiss() }
                        .foregroundColor(AppColor.textSecondary)
                }
            }
        }
    }

    // Parses raw GPT block into structural sections
    struct AnalysisSection {
        let title: String
        let icon: String
        let content: String
    }

    private func parseAnalysis(_ raw: String) -> [AnalysisSection] {
        var list: [AnalysisSection] = []
        let parts = raw.components(separatedBy: "\n\n")

        for part in parts {
            if part.contains("【發生什麼】") {
                let clean = part.replacingOccurrences(of: "【發生什麼】\n", with: "").replacingOccurrences(of: "【發生什麼】", with: "")
                list.append(AnalysisSection(title: "發生什麼", icon: "arrow.left.and.right.circle.fill", content: clean))
            } else if part.contains("【跟你有關】") {
                let clean = part.replacingOccurrences(of: "【跟你有關】\n", with: "").replacingOccurrences(of: "【跟你有關】", with: "")
                list.append(AnalysisSection(title: "與你有關", icon: "heart.text.square.fill", content: clean))
            } else if part.contains("【可以留意】") {
                let clean = part.replacingOccurrences(of: "【可以留意】\n", with: "").replacingOccurrences(of: "【可以留意】", with: "")
                list.append(AnalysisSection(title: "可以留意", icon: "eye.circle.fill", content: clean))
            }
        }

        // Fallback in case format doesn't contain braces
        if list.isEmpty {
            list.append(AnalysisSection(title: "AI 白話解讀", icon: "sparkles", content: raw))
        }

        return list
    }
}
