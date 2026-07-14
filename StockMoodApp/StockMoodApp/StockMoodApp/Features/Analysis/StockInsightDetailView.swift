import SwiftUI

/// 8e 個股觀點詳情:AI 綜合觀點卡(多空溫度計)+ 訊號卡 + 白話總結。
struct StockInsightDetailView: View {
    let symbol: String
    let name: String
    /// 觀察清單(11f)點入時改為「觀察風向」;持股詳情維持「白話總結」
    var plainSummaryLabel: String = "白話總結"
    @StateObject private var viewModel = StockInsightDetailViewModel()
    @State private var selectedSignal: NewsSignal?

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
                                Button {
                                    selectedSignal = signal
                                    HapticManager.shared.triggerImpact(style: .light)
                                } label: {
                                    NewsSignalCard(signal: signal, showsDisclosure: true)
                                }
                                .buttonStyle(.plain)
                                .accessibilityHint("開啟指標解釋、計算方式與資料來源")
                                .entrance(index: index + 2, stagger: 0.09)
                            }
                        }
                        .padding(.top, 10)

                        // 白話總結 / 觀察風向(最後進場)
                        PlainSummaryBlock(label: plainSummaryLabel, content: detail.plainSummary)
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
        .sheet(item: $selectedSignal) { signal in
            SignalExplanationSheet(signal: signal)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
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

// MARK: - 訊號詳細解釋

private struct SignalExplanationSheet: View {
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
