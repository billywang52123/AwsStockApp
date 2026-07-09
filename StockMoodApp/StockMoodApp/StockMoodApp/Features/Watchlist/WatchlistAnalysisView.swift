import SwiftUI

// MARK: - 11e/11f 共用 segmented control(bg/track R16 內距 4,選中段白底陰影)

struct AnalysisSegmentedControl<Segment: Hashable>: View {
    struct Option {
        let value: Segment
        let title: String
        let icon: String?
        let count: Int?
        let countTint: (bg: Color, text: Color)?
    }

    let options: [Option]
    @Binding var selection: Segment

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                segmentButton(option)
            }
        }
        .padding(4)
        .background(AppColor.bgTrack)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func segmentButton(_ option: Option) -> some View {
        let isSelected = selection == option.value
        return Button {
            guard !isSelected else { return }
            HapticManager.shared.triggerSelection()
            withAnimation(.easeOut(duration: 0.2)) { selection = option.value }
        } label: {
            HStack(spacing: 5) {
                if let icon = option.icon {
                    Image(systemName: icon)
                        .font(.system(size: 13))
                        .foregroundColor(AppColor.watchStarIcon)
                }
                Text(option.title)
                    .font(.system(size: 14, weight: isSelected ? .heavy : .bold, design: .rounded))
                    .foregroundColor(isSelected ? AppColor.inkPrimary : AppColor.inkTertiary)
                if let count = option.count {
                    Text("\(count)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(isSelected ? (option.countTint?.text ?? AppColor.inkSecondary) : AppColor.inkTertiary)
                        .padding(.vertical, 2)
                        .padding(.horizontal, 7)
                        .background(isSelected ? (option.countTint?.bg ?? AppColor.bgTrack) : AppColor.bgTrack)
                        .clipShape(Capsule())
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(isSelected ? AppColor.cardBackground : Color.clear)
                    .shadow(color: Color(hex: "786446").opacity(isSelected ? 0.1 : 0), radius: 5, x: 0, y: 4)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 11e · 觀察清單分析 WatchlistAnalysisView
/// 結構與 8a 一致但資料源是觀察清單:不出現市值/損益卡,
/// 產業分布語氣降級為資訊陳列,重點是「與庫存重疊提醒」。
struct WatchlistAnalysisSection: View {
    @ObservedObject var viewModel: AnalysisViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !viewModel.watchlists.isEmpty {
                filterChips
                    .padding(.top, 14)
            }

            if let watch = viewModel.watchAnalysis {
                if watch.watchCount == 0 {
                    emptyState(watch)
                        .padding(.top, 40)
                } else {
                    scoreCard(watch)
                        .padding(.top, 14)
                        .entrance(index: 0)

                    exposureCard(watch)
                        .padding(.top, 12)
                        .entrance(index: 1)

                    if let notice = watch.overlapNotice {
                        // 與庫存重疊提醒:本頁最重要的決策輔助資訊
                        RiskNoticeCard(
                            notice: RiskNotice(
                                severity: .amber,
                                badge: "注意",
                                title: notice.title,
                                body: notice.body,
                                highlight: notice.highlight,
                                plainTalk: notice.plainTalk
                            ),
                            index: 0
                        )
                        .padding(.top, 12)
                        .entrance(index: 2)
                    }

                    Text("觀察清單不計市值損益,分析僅供參考")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundColor(AppColor.inkFaint)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 20)
                }
            }
        }
    }

    private func emptyState(_ watch: WatchlistAnalysis) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "star")
                .font(.system(size: 36))
                .foregroundColor(AppColor.watchStarIcon.opacity(0.6))
            Text(watch.trendNote)
                .font(.system(size: 13, design: .rounded))
                .foregroundColor(AppColor.inkTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    // 清單篩選 chips:「全部」+ 各清單
    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterChip(title: "全部", id: nil)
                ForEach(viewModel.watchlists) { list in
                    filterChip(title: list.name, id: list.id)
                }
            }
        }
    }

    private func filterChip(title: String, id: String?) -> some View {
        let isSelected = viewModel.watchFilterId == id
        return Button {
            HapticManager.shared.triggerSelection()
            Task { await viewModel.applyWatchFilter(id) }
        } label: {
            Text(title)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(isSelected ? .white : AppColor.inkTertiary)
                .padding(.vertical, 7)
                .padding(.horizontal, 14)
                .background(isSelected ? AppColor.inkPrimary : AppColor.cardBackground)
                .clipShape(Capsule())
                .shadow(color: Color(hex: "786446").opacity(isSelected ? 0 : 0.05), radius: 4, x: 0, y: 3)
        }
        .buttonStyle(.plain)
    }

    // 清單平均分數卡:amber 漸層(取代庫存分析的紫漸層市值卡位置)
    private func scoreCard(_ watch: WatchlistAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("清單平均 AI 評分")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .kerning(1)
                .foregroundColor(.white.opacity(0.75))

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                CountUpText(value: Double(watch.averageScore), format: { String(format: "%.0f", $0) })
                    .font(.system(size: 38, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                Text("/100")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.7))
            }
            .padding(.top, 6)

            Text("\(watch.watchCount) 檔觀察中 · \(watch.trendNote)")
                .font(.system(size: 12, design: .rounded))
                .monospacedDigit()
                .foregroundColor(.white.opacity(0.7))
                .padding(.top, 2)

            Rectangle()
                .fill(Color.white.opacity(0.2))
                .frame(height: 1)
                .padding(.vertical, 14)

            HStack(spacing: 8) {
                whitePill("看好 \(watch.bullishCount)")
                whitePill("中性 \(watch.neutralCount)")
                whitePill("短線留意 \(watch.cautionCount)")
                Spacer()
            }
        }
        .padding(22)
        .background(
            LinearGradient(
                colors: [AppColor.watchGradientTop, AppColor.watchGradientBottom],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: AppColor.watchGradientBottom.opacity(0.3), radius: 16, x: 0, y: 14)
    }

    private func whitePill(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundColor(.white)
            .padding(.vertical, 4)
            .padding(.horizontal, 10)
            .background(Color.white.opacity(0.18))
            .clipShape(Capsule())
    }

    // 清單產業分布(同 8a 曝險 bar,但無警示 pill — 未持有,語氣降級為資訊陳列)
    private func exposureCard(_ watch: WatchlistAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("清單產業分布")
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundColor(AppColor.inkPrimary)

            ExposureBarView(segments: watch.exposure)
                .padding(.top, 14)

            Text(watch.exposureNote)
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
}

// MARK: - 11f · 觀點「觀察清單」分頁列(同 8d 列樣式 + AI 評分 pill,subtitle 為清單名)

struct WatchInsightRow: View {
    let item: WatchInsightItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                IndustryAvatar(name: item.name, industry: item.industry)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.name)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(AppColor.inkPrimary)
                    Text("\(item.symbol) · \(item.watchlistName)")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundColor(AppColor.inkQuaternary)
                        .lineLimit(1)
                }
                Spacer()
                Text("AI 評分 \(item.aiScore)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(AppColor.watchScoreStrong)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 10)
                    .background(AppColor.watchScoreBg)
                    .clipShape(Capsule())
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
