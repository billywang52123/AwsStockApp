import SwiftUI

/// 分析分頁:庫存分析(8a/8b/8c)與個股 AI 觀點(8d),個股列點擊 push 至觀點詳情(8e)。
struct PortfolioAnalysisView: View {
    @Binding var activeTab: Int
    @StateObject private var viewModel = AnalysisViewModel()
    @State private var mode: AnalysisMode = .portfolio
    @State private var outlookFilter: Outlook? = nil
    // 11e/11f:持股與觀察清單分頁(資料嚴格分離,不合併列表)
    @State private var analysisSource: DataSource = .holdings
    @State private var insightSource: DataSource = .holdings

    enum AnalysisMode: String, CaseIterable {
        case portfolio = "庫存分析"
        case insights = "個股觀點"
    }

    enum DataSource: Hashable {
        case holdings
        case watchlist
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppColor.background.ignoresSafeArea()

                if viewModel.isLoading {
                    ProgressView("AI 正在整理你的持股...")
                } else if viewModel.hasError && viewModel.analysis == nil {
                    ErrorStateView(message: viewModel.errorMessage) {
                        Task { await viewModel.load() }
                    }
                } else if let analysis = viewModel.analysis, analysis.holdingsCount == 0,
                          (viewModel.watchAnalysis?.watchCount ?? 0) == 0 {
                    EmptyStateView(
                        title: "還沒有可分析的持股",
                        message: "先到「持股」分頁加入你的股票，AI 就會幫你整理市值、風險與每一檔的觀點。",
                        buttonTitle: "去新增持股"
                    ) {
                        activeTab = 2
                    }
                } else if let analysis = viewModel.analysis {
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 0) {
                            // 10d 就地說明:分析用到什麼資料,開頁就講
                            TrustNote(text: "分析只用你的持股組合(代號+權重),不含任何身分資料")
                                .padding(.bottom, 10)

                            modePicker
                                .padding(.bottom, 16)

                            switch mode {
                            case .portfolio:
                                portfolioSection(analysis)
                            case .insights:
                                insightsSection
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom, 40)
                    }
                    .refreshable { await viewModel.load() }
                }
            }
            .navigationTitle("分析")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: StockInsightSummary.self) { item in
                StockInsightDetailView(symbol: item.symbol, name: item.name)
            }
            .navigationDestination(for: HoldingDetail.self) { holding in
                StockInsightDetailView(symbol: holding.symbol, name: holding.name)
            }
            .task { await viewModel.load() }
        }
    }

    // MARK: - 模式切換(庫存分析 / 個股觀點)
    private var modePicker: some View {
        HStack(spacing: 8) {
            ForEach(AnalysisMode.allCases, id: \.self) { candidate in
                Button {
                    guard mode != candidate else { return }
                    HapticManager.shared.triggerSelection()
                    withAnimation(.easeOut(duration: 0.25)) { mode = candidate }
                } label: {
                    Text(candidate.rawValue)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(mode == candidate ? .white : AppColor.inkTertiary)
                        .padding(.vertical, 9)
                        .frame(maxWidth: .infinity)
                        .background(mode == candidate ? AppColor.primary : AppColor.bgTrack)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 8)
    }

    // MARK: - 8a + 8b + 8c ↔ 11e(庫存分析 / 觀察清單分析)
    @ViewBuilder
    private func portfolioSection(_ analysis: PortfolioAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // 大標:副標依 segment 切換
            Text("投組分析")
                .font(.system(size: 30, weight: .heavy, design: .rounded))
                .foregroundColor(AppColor.inkPrimary)
            Text(analysisSource == .holdings ? "AI 先幫你看懂自己的投資組合" : "買了的和還在看的,分開分析")
                .font(.system(size: 14, design: .rounded))
                .foregroundColor(AppColor.inkTertiary)
                .padding(.top, 4)

            // 11e segmented control(庫存分析 / 觀察清單分析)
            AnalysisSegmentedControl(
                options: [
                    .init(value: DataSource.holdings, title: "庫存分析", icon: nil, count: nil, countTint: nil),
                    .init(value: DataSource.watchlist, title: "觀察清單分析", icon: "star.fill", count: nil, countTint: nil),
                ],
                selection: $analysisSource
            )
            .padding(.top, 16)

            // 內容 crossfade,不做位移(避免資料類型混淆的錯覺)
            Group {
                switch analysisSource {
                case .holdings:
                    holdingsAnalysisBody(analysis)
                case .watchlist:
                    WatchlistAnalysisSection(viewModel: viewModel)
                }
            }
            .id(analysisSource)
            .transition(.opacity)
        }
        .animation(.easeOut(duration: 0.25), value: analysisSource)
    }

    // 8a + 8b + 8c 原庫存分析內容
    @ViewBuilder
    private func holdingsAnalysisBody(_ analysis: PortfolioAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // 投組總市值卡
            summaryCard(analysis)
                .padding(.top, 20)
                .entrance(index: 0)

            // 分數雙卡
            HStack(spacing: 12) {
                ScoreTile(label: "風險分數", score: analysis.riskScore,
                          note: analysis.riskNote, scoreColor: AppColor.riskScore)
                ScoreTile(label: "焦慮溫度", score: analysis.anxietyScore,
                          note: analysis.anxietyNote, scoreColor: AppColor.anxietyScore)
            }
            .padding(.top, 12)
            .entrance(index: 1)

            // 產業曝險卡
            exposureCard(analysis)
                .padding(.top, 12)
                .entrance(index: 2)

            // 8b 持股明細
            Text("持股明細")
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .foregroundColor(AppColor.inkPrimary)
                .padding(.top, 28)
            Text("點任一檔，看 AI 對它的最新觀點")
                .font(.system(size: 13, design: .rounded))
                .foregroundColor(AppColor.inkTertiary)
                .padding(.top, 2)

            VStack(spacing: 11) {
                ForEach(Array(analysis.holdings.enumerated()), id: \.element.id) { index, holding in
                    NavigationLink(value: holding) {
                        HoldingRow(holding: holding)
                    }
                    .buttonStyle(.plain)
                    .entrance(index: index + 3, stagger: 0.06)
                }
            }
            .padding(.top, 14)

            Text("共 \(analysis.holdingsCount) 檔持股，完整資料已自動帶入 AI 診斷")
                .font(.system(size: 12, design: .rounded))
                .foregroundColor(AppColor.inkFaint)
                .frame(maxWidth: .infinity)
                .padding(.top, 12)

            // 8c 風險提醒
            if !analysis.riskNotices.isEmpty {
                Text("AI 看出 \(analysis.riskNotices.count) 個要留意的地方")
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .foregroundColor(AppColor.inkPrimary)
                    .lineSpacing(8)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 32)
                Text("不是要你馬上行動，先知道就好")
                    .font(.system(size: 14, design: .rounded))
                    .foregroundColor(AppColor.inkTertiary)
                    .padding(.top, 6)

                VStack(spacing: 12) {
                    ForEach(Array(analysis.riskNotices.enumerated()), id: \.element.id) { index, notice in
                        RiskNoticeCard(notice: notice, index: index)
                            .entrance(index: index, stagger: 0.12)
                    }
                }
                .padding(.top, 20)

                // CTA:抽安心卡
                Button {
                    HapticManager.shared.triggerImpact(style: .light)
                    activeTab = 1
                } label: {
                    Text("求一支安心籤，看怎麼辦")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(AppColor.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .shadow(color: AppColor.primary.opacity(0.35), radius: 13, x: 0, y: 10)
                }
                .buttonStyle(PressScaleButtonStyle())
                .padding(.top, 20)
            }

            DisclaimerBlock()
                .padding(.top, 12)
        }
    }

    // 8a 投組總市值卡(紫色漸層)
    private func summaryCard(_ analysis: PortfolioAnalysis) -> some View {
        let pnlPositive = analysis.unrealizedPnl >= 0
        return VStack(alignment: .leading, spacing: 0) {
            Text("投組總市值")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .kerning(1)
                .foregroundColor(.white.opacity(0.7))

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                CountUpText(value: analysis.totalMarketValue, format: { StockFormat.wan($0) })
                    .font(.system(size: 38, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                Text("萬")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
            .padding(.top, 6)

            Text("約 \(StockFormat.ntd(analysis.totalMarketValue)) · 共 \(analysis.holdingsCount) 檔持股")
                .font(.system(size: 12, design: .rounded))
                .monospacedDigit()
                .foregroundColor(.white.opacity(0.6))
                .padding(.top, 2)

            Rectangle()
                .fill(Color.white.opacity(0.18))
                .frame(height: 1)
                .padding(.vertical, 14)

            HStack {
                Text("未實現損益")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundColor(.white.opacity(0.75))
                CountUpText(value: analysis.unrealizedPnl, format: { StockFormat.signedWan($0) })
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .foregroundColor(pnlPositive ? AppColor.pnlOnGradient : Color(hex: "CFE8D8"))
                Spacer()
                Text(StockFormat.signedPercent(analysis.unrealizedPnlPercent))
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(pnlPositive ? AppColor.pnlOnGradient : Color(hex: "CFE8D8"))
                    .padding(.vertical, 4)
                    .padding(.horizontal, 12)
                    .background(Color.white.opacity(0.16))
                    .clipShape(Capsule())
            }
        }
        .padding(22)
        .background(
            LinearGradient(
                colors: [AppColor.gradientCardTop, AppColor.gradientCardBottom],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: AppColor.gradientCardBottom.opacity(0.30), radius: 16, x: 0, y: 14)
    }

    // 8a 產業曝險卡
    private func exposureCard(_ analysis: PortfolioAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("產業配置曝險")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundColor(AppColor.inkPrimary)
                Spacer()
                if analysis.techExposurePercent >= 50 {
                    Text("科技類達 \(String(format: "%.1f%%", analysis.techExposurePercent))")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(AppColor.amberStrong)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 10)
                        .background(AppColor.amberIconBg)
                        .clipShape(Capsule())
                }
            }

            ExposureBarView(segments: analysis.exposure)
                .padding(.top, 14)

            Text(analysis.exposureNote)
                .font(.system(size: 11, design: .rounded))
                .foregroundColor(AppColor.inkTertiary)
                .lineSpacing(6)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppColor.bgInset)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.top, 12)
        }
        .padding(20)
        .background(AppColor.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Color(hex: "786446").opacity(0.06), radius: 9, x: 0, y: 6)
    }

    // MARK: - 8d ↔ 11f 個股 AI 觀點(我的持股 / 觀察清單分頁)
    @ViewBuilder
    private var insightsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("個股 AI 觀點")
                .font(.system(size: 30, weight: .heavy, design: .rounded))
                .foregroundColor(AppColor.inkPrimary)
            Text(insightSource == .holdings ? "每檔持股，AI 都幫你追了最新變化" : "還沒買的,AI 也幫你先盯著")
                .font(.system(size: 14, design: .rounded))
                .foregroundColor(AppColor.inkTertiary)
                .padding(.top, 4)

            // 11f segmented control:持股/觀察完全分開,避免把「還沒買的評分」當成「已持有的觀點」
            AnalysisSegmentedControl(
                options: [
                    .init(value: DataSource.holdings, title: "我的持股", icon: nil,
                          count: viewModel.insights?.items.count,
                          countTint: nil),
                    .init(value: DataSource.watchlist, title: "觀察清單", icon: nil,
                          count: viewModel.watchInsights?.items.count,
                          countTint: (bg: AppColor.watchStarBadgeBg, text: AppColor.watchScoreStrong)),
                ],
                selection: $insightSource
            )
            .padding(.top, 16)

            Group {
                switch insightSource {
                case .holdings:
                    holdingInsightsBody
                case .watchlist:
                    watchInsightsBody
                }
            }
            .id(insightSource)
            .transition(.opacity)

            DisclaimerBlock(text: "觀點由 AI 整理近期價格與大盤資料，僅供參考")
                .padding(.top, 24)
        }
        .animation(.easeOut(duration: 0.25), value: insightSource)
    }

    // 11f 觀察清單分頁
    @ViewBuilder
    private var watchInsightsBody: some View {
        if let watchInsights = viewModel.watchInsights {
            if watchInsights.items.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "star")
                        .font(.system(size: 36))
                        .foregroundColor(AppColor.watchStarIcon.opacity(0.6))
                    Text("觀察清單還沒有股票\n到持股頁左上角建立清單、加入想追蹤的股票")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundColor(AppColor.inkTertiary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(5)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
            } else {
                HStack(spacing: 8) {
                    watchCountChip(.bullish, count: watchInsights.bullishCount)
                    watchCountChip(.neutral, count: watchInsights.neutralCount)
                    watchCountChip(.caution, count: watchInsights.cautionCount)
                }
                .padding(.top, 16)

                VStack(spacing: 11) {
                    ForEach(Array(watchInsights.items.enumerated()), id: \.element.id) { index, item in
                        WatchInsightRow(item: item)
                            .entrance(index: index, stagger: 0.06)
                    }
                }
                .padding(.top, 16)
            }
        }
    }

    private func watchCountChip(_ outlook: Outlook, count: Int) -> some View {
        Text("\(outlook.label) \(count)")
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundColor(outlook.textColor)
            .padding(.vertical, 6)
            .padding(.horizontal, 13)
            .background(outlook.bgColor)
            .clipShape(Capsule())
    }

    // 8d 我的持股分頁(原內容)
    @ViewBuilder
    private var holdingInsightsBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let insights = viewModel.insights {
                // 統計 chips(可點擊篩選,再點一次取消)
                HStack(spacing: 8) {
                    outlookChip(.bullish, count: insights.bullishCount, index: 0)
                    outlookChip(.neutral, count: insights.neutralCount, index: 1)
                    outlookChip(.caution, count: insights.cautionCount, index: 2)
                }
                .padding(.top, 16)

                let filtered = insights.items.filter { outlookFilter == nil || $0.outlook == outlookFilter }

                VStack(spacing: 11) {
                    ForEach(Array(filtered.enumerated()), id: \.element.id) { index, item in
                        NavigationLink(value: item) {
                            insightRow(item)
                        }
                        .buttonStyle(.plain)
                        .entrance(index: index, stagger: 0.06)
                    }
                }
                .padding(.top, 16)
                .animation(.easeOut(duration: 0.25), value: outlookFilter)

                if filtered.isEmpty {
                    Text("這個分類目前沒有持股")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundColor(AppColor.inkFaint)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 32)
                }
            }
        }
    }

    private func outlookChip(_ outlook: Outlook, count: Int, index: Int) -> some View {
        let isSelected = outlookFilter == outlook
        return Button {
            HapticManager.shared.triggerImpact(style: .light)
            withAnimation(.easeOut(duration: 0.25)) {
                outlookFilter = isSelected ? nil : outlook
            }
        } label: {
            Text("\(outlook.label) \(count)")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundColor(outlook.textColor)
                .padding(.vertical, 6)
                .padding(.horizontal, 13)
                .background(outlook.bgColor)
                .clipShape(Capsule())
                .overlay(
                    Capsule().strokeBorder(isSelected ? outlook.textColor : .clear, lineWidth: 1.5)
                )
        }
        .buttonStyle(.plain)
        .entrance(index: index, stagger: 0.06)
    }

    private func insightRow(_ item: StockInsightSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                IndustryAvatar(name: item.name, industry: item.industry)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.name)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(AppColor.inkPrimary)
                    Text("\(item.symbol) · 權重 \(String(format: "%.1f%%", item.weightPercent))")
                        .font(.system(size: 11, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(AppColor.inkQuaternary)
                }
                Spacer()
                OutlookBadge(outlook: item.outlook)
            }

            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "newspaper")
                    .font(.system(size: 13))
                    .foregroundColor(AppColor.inkFaint)
                Text(item.headline)
                    .font(.system(size: 12, design: .rounded))
                    .foregroundColor(AppColor.inkTertiary)
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 15)
        .padding(.horizontal, 17)
        .background(AppColor.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: Color(hex: "786446").opacity(0.06), radius: 9, x: 0, y: 6)
    }
}

// MARK: - 按壓縮放(CTA:按下 0.97、放開 spring 回彈)
struct PressScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}
