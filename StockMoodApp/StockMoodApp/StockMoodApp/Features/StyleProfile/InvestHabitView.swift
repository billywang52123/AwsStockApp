import SwiftUI

/// 16d 持股投資習慣:由持股與更新紀錄推算,使用者免填寫。
struct InvestHabitView: View {
    @StateObject private var viewModel = InvestmentProfileViewModel()
    @State private var barAnimated = false

    var body: some View {
        ZStack {
            AppColor.background.ignoresSafeArea()

            if viewModel.isLoading && viewModel.profile == nil {
                ProgressView("正在整理你的持股習慣...")
            } else if let profile = viewModel.profile {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("投資習慣")
                            .font(.system(size: 26, weight: .heavy, design: .serif))
                            .foregroundColor(AppColor.inkPrimary)
                        Text("從你的持股與更新紀錄整理，不用自己填")
                            .font(.system(size: 12.5, design: .rounded))
                            .foregroundColor(AppColor.inkTertiary)
                            .padding(.top, 4)

                        // 習慣標籤 chips
                        habitTags(profile)
                            .padding(.top, 16)
                            .entrance(index: 0, stagger: 0.1)

                        // 習慣統計卡
                        habitStatCard(profile)
                            .padding(.top, 16)
                            .entrance(index: 1, stagger: 0.1)

                        // 一致性對照卡
                        consistencyCard(profile)
                            .padding(.top, 12)
                            .entrance(index: 2, stagger: 0.1)

                        DisclaimerBlock(text: "習慣統計依你輸入的持股計算，僅供參考，不構成投資建議")
                            .padding(.top, 16)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 40)
                }
                .refreshable { await viewModel.load() }
            } else if viewModel.hasError {
                ErrorStateView(message: viewModel.errorMessage) {
                    Task { await viewModel.load() }
                }
            }
        }
        .navigationTitle("投資習慣")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
    }

    // MARK: - 習慣標籤 chips

    private func habitTags(_ profile: InvestmentProfileRead) -> some View {
        let metrics = profile.portfolioMetrics
        return HabitTagChips(items: [
            HabitTag(text: profile.investmentHabit.label,
                     bg: AppColor.primaryBgTint, fg: Color(hex: "5A5794")),
            HabitTag(text: profile.observedStyle.label,
                     bg: AppColor.downBgTint, fg: Color(hex: "4E7A62")),
            HabitTag(text: "持股 \(metrics.holdingCount) 檔 · \(metrics.industryCount) 類產業",
                     bg: AppColor.amberIconBg, fg: Color(hex: "A87F3E")),
        ])
    }

    // MARK: - 習慣統計卡(四段)

    private func habitStatCard(_ profile: InvestmentProfileRead) -> some View {
        let metrics = profile.portfolioMetrics
        return VStack(alignment: .leading, spacing: 16) {
            // 持股集中度(含小型 bar)
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text("持股集中度")
                        .font(.system(size: 13.5, weight: .bold, design: .rounded))
                        .foregroundColor(AppColor.inkPrimary)
                    Spacer()
                    Text("最大 \(String(format: "%.1f%%", metrics.topHoldingWeight))")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(AppColor.primary)
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color(hex: "EFEDEA"))
                        Capsule()
                            .fill(LinearGradient(colors: [Color(hex: "9A9EE8"), AppColor.primary],
                                                 startPoint: .leading, endPoint: .trailing))
                            .frame(width: barAnimated
                                   ? geo.size.width * CGFloat(min(metrics.topHoldingWeight, 100)) / 100
                                   : 0)
                    }
                }
                .frame(height: 8)
                .animation(.spring(response: 0.5, dampingFraction: 0.85), value: barAnimated)

                plainTalk(concentrationTalk(metrics))
            }

            statRow(
                name: "科技類占比",
                value: String(format: "%.1f%%", metrics.techWeight),
                talk: metrics.techWeight >= 50
                    ? "白話說：你的漲跌大部分跟著科技與半導體族群走"
                    : "白話說：科技類比重不高，單一產業事件影響有限"
            )

            statRow(
                name: "近 30 日調整",
                value: "\(metrics.activityCount30d) 次",
                talk: activityTalk(metrics)
            )

            statRow(
                name: "買價資料完整度",
                value: String(format: "%.0f%%", metrics.costCompletionRatio),
                talk: metrics.costCompletionRatio >= 99
                    ? "白話說：買價都填齊了，均價與損益的計算是準的"
                    : "白話說：有些分帳還沒填買價，補齊後習慣推算會更準"
            )
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColor.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Color(hex: "786446").opacity(0.06), radius: 9, x: 0, y: 6)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { barAnimated = true }
        }
    }

    private func statRow(name: String, value: String, talk: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(name)
                    .font(.system(size: 13.5, weight: .bold, design: .rounded))
                    .foregroundColor(AppColor.inkPrimary)
                Spacer()
                Text(value)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(AppColor.primary)
            }
            plainTalk(talk)
        }
    }

    private func plainTalk(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11.5, design: .rounded))
            .foregroundColor(AppColor.inkTertiary)
            .lineSpacing(4)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func concentrationTalk(_ metrics: PortfolioHabitMetrics) -> String {
        if metrics.holdingCount == 0 {
            return "白話說：還沒有持股資料，先加入持股就會開始統計"
        }
        if metrics.topHoldingWeight >= 60 {
            return "白話說：你的整體損益大部分跟著第一大持股走"
        }
        if metrics.topHoldingWeight >= 35 {
            return "白話說：前幾檔持股主導整體感受，屬於中等集中"
        }
        return "白話說：持股相對分散，單一持股對整體影響有限"
    }

    private func activityTalk(_ metrics: PortfolioHabitMetrics) -> String {
        if metrics.activityCount30d == 0 {
            return "白話說：買了就放著，這個月沒有調整"
        }
        if metrics.activityCount30d >= 8 {
            return "白話說：這個月調整較頻繁(買 \(metrics.buyCount30d) · 賣 \(metrics.sellCount30d))，風格可能跟著改變"
        }
        return "白話說：偶爾小調(買 \(metrics.buyCount30d) · 賣 \(metrics.sellCount30d))，多半是微調原本持股"
    }

    // MARK: - 一致性對照卡

    @ViewBuilder
    private func consistencyCard(_ profile: InvestmentProfileRead) -> some View {
        if viewModel.styleConsistent {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle().fill(AppColor.downStrong).frame(width: 26, height: 26)
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("和你的測驗風格一致")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(Color(hex: "3E6650"))
                    Text("測驗說你是\(profile.preferenceStyle.label)，持股習慣也符合 —— AI 的說明口吻維持不變。")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundColor(Color(hex: "5C7A68"))
                        .lineSpacing(5)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColor.downBgTint)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        } else {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle().fill(AppColor.amberBadge).frame(width: 26, height: 26)
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("習慣和測驗有點不一樣")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(AppColor.amberStrong)
                    Text("測驗說你是\(profile.preferenceStyle.label)，實際持股比較像\(profile.observedStyle.label)。說明口吻以測驗為準(你的自述優先)，並補充實際習慣的提醒。")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundColor(AppColor.amberText)
                        .lineSpacing(5)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColor.amberBg)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(AppColor.amberBorder, lineWidth: 1.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}

// MARK: - 習慣標籤

struct HabitTag: Identifiable, Hashable {
    var id: String { text }
    let text: String
    let bg: Color
    let fg: Color
}

/// 習慣標籤 chips 換行排列(gap 8)
struct HabitTagChips: View {
    let items: [HabitTag]

    var body: some View {
        // 標籤數量少,用 LazyVGrid 自適應即可
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8, alignment: .leading)],
                  alignment: .leading, spacing: 8) {
            ForEach(items) { tag in
                Text(tag.text)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(tag.fg)
                    .padding(.vertical, 5)
                    .padding(.horizontal, 13)
                    .background(tag.bg)
                    .clipShape(Capsule())
                    .fixedSize()
            }
        }
    }
}
