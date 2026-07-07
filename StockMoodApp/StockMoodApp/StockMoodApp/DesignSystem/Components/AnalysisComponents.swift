import SwiftUI

// MARK: - 數字格式
enum StockFormat {
    /// 5,327,000 → "532.7"(萬)
    static func wan(_ value: Double) -> String {
        String(format: "%.1f", value / 10_000)
    }

    /// 5327000 → "NT$ 5,327,000"
    static func ntd(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        let text = formatter.string(from: NSNumber(value: value)) ?? "0"
        return "NT$ \(text)"
    }

    /// +21.7 萬 / -3.2 萬
    static func signedWan(_ value: Double) -> String {
        let sign = value >= 0 ? "+" : "-"
        return "\(sign)\(String(format: "%.1f", abs(value) / 10_000)) 萬"
    }

    static func signedPercent(_ value: Double, digits: Int = 2) -> String {
        String(format: "%+.\(digits)f%%", value)
    }
}

// MARK: - 進場動畫(fade + 上移 12pt,可依 index stagger;尊重「減少動態效果」)
struct EntranceModifier: ViewModifier {
    let index: Int
    let baseDelay: Double
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(appeared || reduceMotion ? 1 : 0)
            .offset(y: appeared || reduceMotion ? 0 : 12)
            .onAppear {
                guard !appeared else { return }
                withAnimation(.easeOut(duration: 0.45).delay(Double(index) * baseDelay)) {
                    appeared = true
                }
            }
    }
}

extension View {
    /// 卡片進場:fade + 上移 12pt,stagger(spec 03)
    func entrance(index: Int, stagger: Double = 0.08) -> some View {
        modifier(EntranceModifier(index: index, baseDelay: stagger))
    }
}

// MARK: - Count-up 數字(spec 03:0.8s easeOut,monospacedDigit 防跳動)
struct CountUpText: View {
    let value: Double
    var format: (Double) -> String
    var duration: Double = 0.8
    var delay: Double = 0

    @State private var displayed: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Text(format(displayed))
            .monospacedDigit()
            .onAppear {
                if reduceMotion {
                    displayed = value
                } else {
                    displayed = 0
                    withAnimation(.easeOut(duration: duration).delay(delay)) {
                        displayed = value
                    }
                }
            }
            .onChange(of: value) { _, newValue in
                displayed = newValue
            }
            .contentTransition(.numericText())
            .animation(.easeOut(duration: duration), value: displayed)
    }
}

// MARK: - OutlookBadge(看好 / 中性 / 短線留意 pill)
struct OutlookBadge: View {
    let outlook: Outlook

    var body: some View {
        Text(outlook.label)
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundColor(outlook.textColor)
            .padding(.vertical, 5)
            .padding(.horizontal, 12)
            .background(outlook.bgColor)
            .clipShape(Capsule())
    }
}

// MARK: - 白話盒(accent tint,沿用 ExplanationBlock 樣式語彙)
struct PlainSummaryBlock: View {
    var label: String = "白話總結"
    let content: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(AppColor.primary)
            Text(content)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(AppColor.inkPrimary)
                .lineSpacing(6)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 16)
        .padding(.horizontal, 18)
        .background(AppColor.primaryBgTint)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

// MARK: - DisclaimerBlock(11pt inkFaint 置中)
struct DisclaimerBlock: View {
    var text: String = "內容僅供資訊參考，不構成投資建議。"

    var body: some View {
        Text(text)
            .font(.system(size: 11, design: .rounded))
            .foregroundColor(AppColor.inkFaint)
            .multilineTextAlignment(.center)
            .lineSpacing(5)
            .frame(maxWidth: .infinity)
    }
}

// MARK: - ScoreTile(風險分數 / 焦慮溫度小卡)
struct ScoreTile: View {
    let label: String
    let score: Int
    let note: String
    let scoreColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 12, design: .rounded))
                .foregroundColor(AppColor.inkQuaternary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                CountUpText(value: Double(score), format: { String(format: "%.0f", $0) }, duration: 0.6, delay: 0.2)
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .foregroundColor(scoreColor)
                Text("/100")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundColor(AppColor.inkFaint)
            }
            Text(note)
                .font(.system(size: 11, design: .rounded))
                .foregroundColor(AppColor.inkTertiary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(AppColor.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Color(hex: "786446").opacity(0.06), radius: 9, x: 0, y: 6)
    }
}

// MARK: - ExposureBar(產業曝險堆疊 bar + 圖例)
struct ExposureBarView: View {
    let segments: [ExposureSegment]
    @State private var grown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // 堆疊 bar:分段由左至右依序長出
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
                        IndustryStyle.style(for: segment.industry).color
                            .frame(width: max(0, (geo.size.width - CGFloat(segments.count - 1) * 2) * segment.percent / 100))
                            .scaleEffect(x: grown || reduceMotion ? 1 : 0, anchor: .leading)
                            .animation(.easeOut(duration: 0.4).delay(Double(index) * 0.08), value: grown)
                    }
                }
            }
            .frame(height: 14)
            .clipShape(Capsule())

            // 圖例:2 欄 grid,隨分段 fade-in
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 8) {
                ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(IndustryStyle.style(for: segment.industry).color)
                            .frame(width: 8, height: 8)
                        Text(segment.industry)
                            .font(.system(size: 12, design: .rounded))
                            .foregroundColor(AppColor.inkSecondary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Text(String(format: "%.1f%%", segment.percent))
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundColor(AppColor.inkPrimary)
                    }
                    .opacity(grown || reduceMotion ? 1 : 0)
                    .animation(.easeOut(duration: 0.3).delay(Double(index) * 0.08 + 0.2), value: grown)
                }
            }
        }
        .onAppear { grown = true }
    }
}

// MARK: - SentimentMeter(8e 多空溫度計)
struct SentimentMeter: View {
    /// 0 = 極偏空、50 = 中性、100 = 極偏多
    let score: Int
    @State private var position: Double = 50
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var thumbBorderColor: Color {
        score < 50 ? AppColor.downStrong : (score > 50 ? AppColor.upStrong : AppColor.neutralText)
    }

    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // 軌道:偏空(綠)→ 中性 → 偏多(紅),靜態漸層不流動
                    Capsule()
                        .fill(LinearGradient(
                            colors: [Color(hex: "8FB49C"), Color(hex: "E3DFD4"), Color(hex: "D89B96")],
                            startPoint: .leading, endPoint: .trailing
                        ))
                        .frame(height: 10)
                        .frame(maxHeight: .infinity, alignment: .center)

                    // 滑標:自 50% spring 單次定位,不回彈多次
                    Circle()
                        .fill(Color.white)
                        .overlay(Circle().strokeBorder(thumbBorderColor, lineWidth: 3))
                        .frame(width: 18, height: 18)
                        .shadow(color: Color.black.opacity(0.15), radius: 4, x: 0, y: 3)
                        .offset(x: (geo.size.width - 18) * position / 100)
                }
            }
            .frame(height: 18)

            HStack {
                Text("偏空")
                Spacer()
                Text("中性")
                Spacer()
                Text("偏多")
            }
            .font(.system(size: 11, design: .rounded))
            .foregroundColor(AppColor.inkQuaternary)
        }
        .onAppear {
            if reduceMotion {
                position = Double(score)
            } else {
                position = 50
                withAnimation(.spring(response: 0.8, dampingFraction: 0.85)) {
                    position = Double(score)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    HapticManager.shared.triggerImpact(style: .light)
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel("多空溫度計，分數 \(score)，0 為極偏空、100 為極偏多")
    }
}

// MARK: - NewsSignalCard(8e 新聞/訊號卡)
struct NewsSignalCard: View {
    let signal: NewsSignal
    @State private var labelShown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(signal.source)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(AppColor.inkTertiary)
                    .padding(.vertical, 3)
                    .padding(.horizontal, 9)
                    .background(AppColor.bgTrack)
                    .clipShape(Capsule())
                Spacer()
                Text(signal.directionLabel)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(signal.direction.color)
                    .opacity(labelShown || reduceMotion ? 1 : 0)
            }
            Text(signal.text)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(AppColor.inkPrimary)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 15)
        .padding(.horizontal, 17)
        .background(AppColor.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: Color(hex: "786446").opacity(0.06), radius: 9, x: 0, y: 6)
        .onAppear {
            withAnimation(.easeOut(duration: 0.3).delay(0.35)) {
                labelShown = true
            }
        }
    }
}

// MARK: - RiskNoticeCard(8c 風險提醒卡,rose / amber)
struct RiskNoticeCard: View {
    let notice: RiskNotice
    let index: Int
    @State private var borderShown = false
    @State private var badgeShown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var bg: Color { notice.severity == .rose ? AppColor.roseBg : AppColor.amberBg }
    private var border: Color { notice.severity == .rose ? AppColor.roseBorder : AppColor.amberBorder }
    private var iconBg: Color { notice.severity == .rose ? AppColor.roseIconBg : AppColor.amberIconBg }
    private var textColor: Color { notice.severity == .rose ? AppColor.roseText : AppColor.amberText }
    private var strongColor: Color { notice.severity == .rose ? AppColor.roseStrong : AppColor.amberStrong }
    private var badgeColor: Color { notice.severity == .rose ? AppColor.roseBadge : AppColor.amberBadge }

    /// 內文:關鍵數字(highlight)加粗上色
    private var bodyText: Text {
        guard !notice.highlight.isEmpty,
              let range = notice.body.range(of: notice.highlight) else {
            return Text(notice.body)
        }
        let before = String(notice.body[notice.body.startIndex..<range.lowerBound])
        let after = String(notice.body[range.upperBound...])
        return Text(before)
            + Text(notice.highlight).font(.system(size: 13, weight: .heavy, design: .rounded)).foregroundColor(strongColor)
            + Text(after)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(iconBg)
                        .frame(width: 34, height: 34)
                    Image(systemName: "exclamationmark.circle")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(strongColor)
                }
                Text(notice.title)
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .foregroundColor(AppColor.inkPrimary)
                Spacer()
                Text(notice.badge)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 11)
                    .background(badgeColor)
                    .clipShape(Capsule())
                    .scaleEffect(badgeShown || reduceMotion ? 1 : 0.8)
                    .opacity(badgeShown || reduceMotion ? 1 : 0)
            }

            bodyText
                .font(.system(size: 13, design: .rounded))
                .foregroundColor(AppColor.inkSecondary)
                .lineSpacing(7)
                .fixedSize(horizontal: false, vertical: true)

            Text(notice.plainTalk)
                .font(.system(size: 12, design: .rounded))
                .foregroundColor(textColor)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.7))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 20)
        .background(bg)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(border, lineWidth: 1.5)
                .opacity(borderShown || reduceMotion ? 1 : 0)
        )
        .onAppear {
            // spec 03:描邊延遲 0.4s 淡入;badge 定位後 spring 一次,不重複跳動
            withAnimation(.easeIn(duration: 0.35).delay(0.4 + Double(index) * 0.12)) {
                borderShown = true
            }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7).delay(0.25 + Double(index) * 0.12)) {
                badgeShown = true
            }
        }
    }
}

// MARK: - 產業頭像圈(8b / 8d 共用)
struct IndustryAvatar: View {
    let name: String
    let industry: String

    private var abbreviation: String {
        String(name.prefix(2))
    }

    var body: some View {
        let style = IndustryStyle.style(for: industry)
        ZStack {
            Circle().fill(style.avatarBg)
            Text(abbreviation)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(style.color)
        }
        .frame(width: 40, height: 40)
    }
}

// MARK: - HoldingRow(8b 持股列:主列 + 權重 bar + 註記列)
struct HoldingRow: View {
    let holding: HoldingDetail
    @State private var barFilled = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var pnlColor: Color {
        holding.pnl >= 0 ? AppColor.upText : AppColor.downText
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            // 主列
            HStack(spacing: 10) {
                IndustryAvatar(name: holding.name, industry: holding.industry)
                VStack(alignment: .leading, spacing: 1) {
                    Text(holding.name)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(AppColor.inkPrimary)
                    Text("\(holding.symbol) · \(holding.industry)")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundColor(AppColor.inkQuaternary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text(StockFormat.signedWan(holding.pnl))
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(pnlColor)
                    Text(StockFormat.signedPercent(holding.pnlPercent))
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(pnlColor)
                }
            }

            // 權重 bar:列進場後填色 0 → 權重%
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(AppColor.bgTrack)
                    Capsule()
                        .fill(IndustryStyle.style(for: holding.industry).color)
                        .frame(width: geo.size.width * (barFilled || reduceMotion ? holding.weightPercent : 0) / 100)
                }
            }
            .frame(height: 6)

            // 註記列
            HStack {
                if let shares = holding.shares, let cost = holding.costPrice, let close = holding.closePrice {
                    Text("\(shares.formatted()) 股 · \(cost.formatted(.number.precision(.fractionLength(0...1)))) → \(close.formatted(.number.precision(.fractionLength(0...1))))")
                } else {
                    Text("尚未填寫成本與股數")
                }
                Spacer()
                (Text("權重 ")
                    + Text(String(format: "%.1f%%", holding.weightPercent))
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(AppColor.inkSecondary))
            }
            .font(.system(size: 11, design: .rounded))
            .monospacedDigit()
            .foregroundColor(AppColor.inkQuaternary)
        }
        .padding(.vertical, 15)
        .padding(.horizontal, 17)
        .background(AppColor.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: Color(hex: "786446").opacity(0.06), radius: 9, x: 0, y: 6)
        .onAppear {
            withAnimation(.easeOut(duration: 0.6).delay(0.3)) {
                barFilled = true
            }
        }
    }
}
