import SwiftUI

// MARK: - 共用光效

/// 全息掃光:一道斜向光帶橫掃卡面(閃卡 3.6s / 封面 4.5s 循環)
struct HoloShimmer: ViewModifier {
    var widthFraction: CGFloat = 0.38
    var duration: Double = 3.6
    var opacity: Double = 0.35
    @State private var moving = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.overlay(
            GeometryReader { geo in
                if !reduceMotion {
                    LinearGradient(
                        colors: [.clear, .white.opacity(opacity), .clear],
                        startPoint: .leading, endPoint: .trailing
                    )
                    .frame(width: geo.size.width * widthFraction, height: geo.size.height * 1.6)
                    .rotationEffect(.degrees(18))
                    .offset(x: moving ? geo.size.width * 1.25 : -geo.size.width * 0.65,
                            y: -geo.size.height * 0.3)
                    .animation(.easeInOut(duration: duration).repeatForever(autoreverses: false),
                               value: moving)
                    .onAppear { moving = true }
                }
            }
            .allowsHitTesting(false)
        )
    }
}

extension View {
    func holoShimmer(widthFraction: CGFloat = 0.38, duration: Double = 3.6,
                     opacity: Double = 0.35) -> some View {
        modifier(HoloShimmer(widthFraction: widthFraction, duration: duration, opacity: opacity))
    }
}

/// 閃卡五色流光邊框:conic-gradient 3.5pt 描邊,5s linear 無限旋轉(持續態,不可暫停)
struct FlashcardRing: View {
    var cornerRadius: CGFloat = 26
    var lineWidth: CGFloat = 3.5
    @State private var rotating = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let diagonal = max(geo.size.width, geo.size.height) * 1.6
            AngularGradient(colors: TrustCardColor.flashcardRing, center: .center)
                .frame(width: diagonal, height: diagonal)
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
                .rotationEffect(.degrees(rotating && !reduceMotion ? 360 : 0))
                .animation(.linear(duration: 5).repeatForever(autoreverses: false), value: rotating)
        }
        .mask(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color.white, lineWidth: lineWidth)
        )
        .allowsHitTesting(false)
        .onAppear { rotating = true }
    }
}

// MARK: - 卡片標籤 pill

struct CardTagPill: View {
    let text: String
    let bg: Color
    var fg: Color = .white

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundColor(fg)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(bg)
            .clipShape(Capsule())
    }
}

// MARK: - 15f · 事實卡完成態 `FactCard`(含閃卡)

struct FactCardView: View {
    let pack: DailyPack
    let onChip: (SourceChip) -> Void

    @State private var expandedSymbols: Set<String> = []
    private var fact: FactCardData { pack.fact }
    private var isFlash: Bool { fact.flashcard != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 標籤列
            HStack {
                CardTagPill(text: "事實卡 · 可驗證",
                            bg: TrustCardColor.factLabelBg, fg: TrustCardColor.factLabelText)
                Spacer()
                Text("1/3")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(AppColor.inkQuaternary)
            }
            .padding(.bottom, 14)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    // 頂部:庫存今日市值 + 今日漲跌並列
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("庫存今日市值")
                                .font(.system(size: 12, design: .rounded))
                                .foregroundColor(AppColor.inkTertiary)
                            Text(fact.totalValueText)
                                .font(.system(size: 34, weight: .heavy, design: .monospaced))
                                .foregroundColor(TrustCardColor.factNumber)
                        }
                        Spacer()
                        Text(String(format: "%+.2f%%", fact.totalChangePercent))
                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                            .foregroundColor(changeColor(fact.totalChangePercent))
                    }
                    SourceChipView(chip: fact.totalChip, onTap: onChip)

                    // 閃卡觸發原因盒(寫死數據事件)
                    if let flash = fact.flashcard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("閃卡觸發:\(flash.eventText)")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundColor(AppColor.amberText)
                                .lineSpacing(4)
                            SourceChipView(chip: flash.chip, onTap: onChip)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(AppColor.amberBg)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(AppColor.amberBorder, lineWidth: 1)
                        )
                    }

                    // 個股明細(可展開)
                    VStack(spacing: 8) {
                        ForEach(fact.stocks) { stock in
                            ExpandableStockRow(
                                stock: stock,
                                isExpanded: expandedSymbols.contains(stock.symbol),
                                onToggle: { toggle(stock.symbol) },
                                onChip: onChip
                            )
                        }
                    }

                    Text(fact.footnote)
                        .font(.system(size: 10, design: .rounded))
                        .foregroundColor(AppColor.inkQuaternary)
                        .lineSpacing(4)
                }
                .padding(.bottom, 6)
            }
        }
        .padding(18)
        .background(TrustCardColor.factBg)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(TrustCardColor.factBorder, lineWidth: isFlash ? 0 : 1.5)
        )
        .overlay { if isFlash { FlashcardRing() } }
        .overlay(alignment: .topTrailing) {
            if isFlash {
                Text("✦ 閃卡")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        LinearGradient(colors: TrustCardColor.flashcardTag,
                                       startPoint: .leading, endPoint: .trailing)
                    )
                    .clipShape(Capsule())
                    .offset(x: -12, y: -10)
            }
        }
        .modifier(ConditionalShimmer(enabled: isFlash))
        .shadow(color: Color(red: 120/255, green: 100/255, blue: 70/255).opacity(0.22),
                radius: 25, x: 0, y: 24)
        .onAppear {
            expandedSymbols = Set(fact.stocks.filter(\.expandedDefault).map(\.symbol))
        }
    }

    private func toggle(_ symbol: String) {
        HapticManager.shared.triggerImpact(style: .light)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            if expandedSymbols.contains(symbol) {
                expandedSymbols.remove(symbol)
            } else {
                expandedSymbols.insert(symbol)
            }
        }
    }
}

/// 閃卡才疊掃光(38% 寬 3.6s 循環)
private struct ConditionalShimmer: ViewModifier {
    let enabled: Bool
    func body(content: Content) -> some View {
        if enabled {
            content.holoShimmer(widthFraction: 0.38, duration: 3.6)
        } else {
            content
        }
    }
}

/// 15f · 個股明細展開列
struct ExpandableStockRow: View {
    let stock: FactStock
    let isExpanded: Bool
    let onToggle: () -> Void
    let onChip: (SourceChip) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button(action: onToggle) {
                HStack(spacing: 8) {
                    Text(stock.name)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(AppColor.inkPrimary)
                    Text(stock.symbol)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(AppColor.inkQuaternary)
                    Spacer()
                    Text(String(format: "%+.2f%%", stock.changePercent))
                        .font(.system(size: 12.5, weight: .bold, design: .monospaced))
                        .foregroundColor(changeColor(stock.changePercent))
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(AppColor.inkQuaternary)
                }
                .padding(.horizontal, 12)
                .frame(minHeight: 44)   // 最小點擊 44
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(spacing: 7) {
                    ForEach(stock.rows) { row in
                        HStack(spacing: 8) {
                            Text(row.label)
                                .font(.system(size: 11.5, design: .rounded))
                                .foregroundColor(AppColor.inkTertiary)
                            Text(row.value)
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundColor(TrustCardColor.factNumber)
                            Spacer()
                            if let chip = row.chip {
                                SourceChipView(chip: chip, onTap: onChip)
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// 台股慣例:漲 = 紅系、跌 = 綠系(降飽和)
func changeColor(_ change: Double) -> Color {
    if change > 0 { return AppColor.upText }
    if change < 0 { return AppColor.downText }
    return AppColor.neutralText
}

// MARK: - 15g · 推論卡完成態 `InferenceCard`(推理鏈展開)

struct InferenceCardView: View {
    let pack: DailyPack
    let onChip: (SourceChip) -> Void
    let onGlossary: (GlossaryTerm) -> Void

    @State private var chainExpanded = true
    private var inference: InferenceCardData { pack.inference }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                CardTagPill(text: "AI 推論", bg: TrustCardColor.inferenceLabelBg)
                Spacer()
                Text("這是判斷,不是事實")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundColor(TrustCardColor.inferenceMuted)
            }
            .padding(.bottom, 14)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    // 結論句
                    Text(inference.conclusion)
                        .font(.system(size: 20, weight: .heavy, design: .rounded))
                        .foregroundColor(TrustCardColor.inferenceText)
                        .lineSpacing(9)
                        .fixedSize(horizontal: false, vertical: true)

                    // 虛線術語 → 名詞小卡
                    if !inference.terms.isEmpty {
                        HStack(spacing: 10) {
                            ForEach(inference.terms) { term in
                                Button {
                                    HapticManager.shared.triggerImpact(style: .light)
                                    onGlossary(term)
                                } label: {
                                    VStack(spacing: 2) {
                                        Text(term.term)
                                            .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                                            .foregroundColor(TrustCardColor.inferenceChipText)
                                        DashedLine()
                                            .stroke(TrustCardColor.inferenceChipText,
                                                    style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                                            .frame(height: 1.5)
                                    }
                                    .fixedSize()
                                }
                                .buttonStyle(.plain)
                            }
                            Spacer()
                        }
                    }

                    // 推理鏈 toggle 列
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            chainExpanded.toggle()
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Text("推理鏈")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundColor(TrustCardColor.inferenceMuted)
                            Rectangle()
                                .fill(TrustCardColor.inferenceBorder.opacity(0.6))
                                .frame(height: 1)
                            Text(chainExpanded ? "已展開 ⌃" : "展開 ⌄")
                                .font(.system(size: 11, design: .rounded))
                                .foregroundColor(TrustCardColor.inferenceMuted)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    // 推理步驟 ×3:每步是數字,附出處 chip
                    if chainExpanded {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(inference.steps) { step in
                                ReasoningStepRow(step: step, onChip: onChip, onGlossary: onGlossary)
                            }
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    Text(inference.caveat)
                        .font(.system(size: 10.5, design: .rounded))
                        .foregroundColor(TrustCardColor.inferenceMuted)
                        .lineSpacing(6)
                }
                .padding(.bottom, 6)
            }
        }
        .padding(18)
        .background(
            LinearGradient(colors: TrustCardColor.inferenceBg,
                           startPoint: .top, endPoint: .bottom)
        )
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(TrustCardColor.inferenceBorder, lineWidth: 1.5)
        )
        .shadow(color: Color(red: 120/255, green: 100/255, blue: 70/255).opacity(0.18),
                radius: 25, x: 0, y: 24)
    }
}

struct DashedLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.width, y: rect.midY))
        return path
    }
}

/// 15g · 推理步驟列 `ReasoningStep`
struct ReasoningStepRow: View {
    let step: ReasoningStep
    let onChip: (SourceChip) -> Void
    let onGlossary: (GlossaryTerm) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(step.number)")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
                .frame(width: 24, height: 24)
                .background(TrustCardColor.inferenceLabelBg)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 7) {
                Text(step.text)
                    .font(.system(size: 12.5, design: .rounded))
                    .foregroundColor(TrustCardColor.inferenceStepNumber)
                    .lineSpacing(7)
                    .fixedSize(horizontal: false, vertical: true)

                if let chip = step.chip {
                    SourceChipView(chip: chip, tint: .inference, onTap: onChip)
                }
                // 第 3 步行為財務學:chip 改「📖 名詞小卡」樣式
                if let glossary = step.glossary {
                    Button {
                        HapticManager.shared.triggerImpact(style: .light)
                        onGlossary(glossary)
                    } label: {
                        HStack(spacing: 3) {
                            Text("📖 名詞小卡:\(glossary.term)")
                                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                            Text("›")
                                .font(.system(size: 10.5, weight: .bold))
                        }
                        .foregroundColor(TrustCardColor.inferenceChipText)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(TrustCardColor.inferenceChipBg)
                        .clipShape(Capsule())
                        .overlay(Capsule().strokeBorder(TrustCardColor.inferenceChipBorder, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - 15h · 社群卡完成態 `CommunityCard`(同學會溫度計)
// 鐵則:社群結構性偏多,只顯示相對這檔自身 30 日基準的變化,絕不顯示絕對多空比

struct CommunityCardView: View {
    let pack: DailyPack
    let onChip: (SourceChip) -> Void

    private var community: CommunityCardData { pack.communityCard }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                CardTagPill(text: "社群卡 · 同學會", bg: TrustCardColor.communityLabelBg)
                Spacer()
                Text("這是氣氛,不是訊號")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundColor(TrustCardColor.communityText.opacity(0.7))
            }
            .padding(.bottom, 14)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    // 聚焦股(同學會討論最熱的一檔)
                    HStack(spacing: 8) {
                        Text(community.stockName)
                            .font(.system(size: 17, weight: .heavy, design: .rounded))
                            .foregroundColor(TrustCardColor.communityText)
                        if !community.stockSymbol.isEmpty {
                            Text(community.stockSymbol)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(TrustCardColor.communityText.opacity(0.55))
                        }
                        Spacer()
                    }

                    if community.hasData {
                        heatSection
                        Divider().overlay(TrustCardColor.communityBorder)
                        sentimentSection
                        if let chip = community.chip {
                            SourceChipView(chip: chip, onTap: onChip)
                        }
                    } else {
                        // 資料不足態:安撫語氣,不做空狀態插畫
                        Text(community.heatText)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundColor(TrustCardColor.communityText)
                            .lineSpacing(8)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.vertical, 18)
                    }
                }
                .padding(.bottom, 6)
            }

            Spacer(minLength: 10)

            // 底部固定附註(分隔線上緣)
            VStack(alignment: .leading, spacing: 8) {
                Divider().overlay(TrustCardColor.communityBorder)
                Text(community.note)
                    .font(.system(size: 10.5, design: .rounded))
                    .foregroundColor(TrustCardColor.communityText.opacity(0.75))
                    .lineSpacing(6)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .background(
            ZStack {
                LinearGradient(colors: TrustCardColor.communityBg,
                               startPoint: .top, endPoint: .bottom)
                // 右上角 150×150 綠光暈裝飾圓(不遮文字)
                Circle()
                    .fill(
                        RadialGradient(colors: [TrustCardColor.communityLabelBg.opacity(0.28), .clear],
                                       center: .center, startRadius: 6, endRadius: 80)
                    )
                    .frame(width: 150, height: 150)
                    .offset(x: 90, y: -160)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(TrustCardColor.communityBorder, lineWidth: 1.5)
        )
        .shadow(color: Color(red: 120/255, green: 100/255, blue: 70/255).opacity(0.18),
                radius: 25, x: 0, y: 24)
    }

    // ── 討論量區:今日 vs 30 日均值,滿版綠條 + 白色均值刻度線 ──

    private var heatSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("今日討論量")
                    .font(.system(size: 11.5, design: .rounded))
                    .foregroundColor(TrustCardColor.communityText.opacity(0.65))
                Text("\(community.postsToday.formatted()) 則")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundColor(TrustCardColor.communityText)
                Spacer()
                Text("30 日均值 \(Int(community.postsBaseline).formatted()) 則")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(TrustCardColor.communityText.opacity(0.55))
            }

            // 9pt 高進度條:綠漸層滿版,白色刻度線標均值位置
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [TrustCardColor.communityLabelBg.opacity(0.55),
                                         TrustCardColor.communityLabelBg],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                    Rectangle()
                        .fill(Color.white)
                        .frame(width: 2.5, height: 13)
                        .offset(x: geo.size.width * community.baselineTickPercent / 100)
                }
            }
            .frame(height: 9)
            .padding(.vertical, 2)

            Text(community.heatText)
                .font(.system(size: 12.5, weight: .bold, design: .rounded))
                .foregroundColor(TrustCardColor.communityText)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // ── 看多/看空溫度區:中線刻度條,中點 = 這檔自身 30 日基準 ──

    private var sentimentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("看多/看空溫度")
                    .font(.system(size: 11.5, weight: .bold, design: .rounded))
                    .foregroundColor(TrustCardColor.communityText.opacity(0.75))
                Spacer()
                Text("vs 這檔自己的 30 日基準")
                    .font(.system(size: 10.5, design: .rounded))
                    .foregroundColor(TrustCardColor.communityText.opacity(0.5))
            }

            if let shift = community.sentimentShiftPercent {
                // 中點為自身基準;偏多向右橙色段、偏空向左(±30% 滿格)
                GeometryReader { geo in
                    let half = geo.size.width / 2
                    let span = min(abs(shift) / 30.0, 1.0) * half
                    ZStack(alignment: .leading) {
                        Capsule().fill(TrustCardColor.communityLabelBg.opacity(0.14))
                        Rectangle()
                            .fill(AppColor.amberBadge)
                            .frame(width: max(span, 3), height: 9)
                            .offset(x: shift >= 0 ? half : half - span)
                        Rectangle()
                            .fill(TrustCardColor.communityText.opacity(0.45))
                            .frame(width: 2, height: 13)
                            .offset(x: half - 1)
                    }
                }
                .frame(height: 9)
                .clipShape(Capsule())
                .padding(.vertical, 2)
            }

            if let sentimentText = community.sentimentText {
                Text(sentimentText)
                    .font(.system(size: 12.5, weight: .bold, design: .rounded))
                    .foregroundColor(TrustCardColor.communityText)
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - 15e · TCG 質感卡背 `CardBackFace`
// 各卡型專屬深色寶石漸層 + 雙層金屬細框 + 內縮 7/11pt 雙細線框 + 四角 L 形角飾
// + 中央 84pt 圓形徽記(實/推/氛,呼吸光暈)+ 45° 菱形線框 ×2 + 卡名/飾線副標/羅馬序號

struct CardBackFace: View {
    let kind: PackCardKind
    /// 前景卡才跑光芒層/掃光/呼吸動畫(後方卡靜止省電)
    var isForeground = false
    /// 包內含閃卡:卡背金色光暈爆發 + 右上「✦ 內有閃卡」pill
    var showsFlashHint = false

    @State private var emblemPulsing = false
    @State private var flashPulsing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var gradient: [Color] {
        switch kind {
        case .fact: return TrustCardColor.cardBackFact
        case .inference: return TrustCardColor.cardBackInference
        case .community: return TrustCardColor.cardBackCommunity
        }
    }

    private var emblemColor: Color {
        switch kind {
        case .fact: return TrustCardColor.cardBackEmblemFact
        case .inference: return TrustCardColor.cardBackEmblemInference
        case .community: return TrustCardColor.cardBackEmblemCommunity
        }
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: gradient,
                           startPoint: .topLeading, endPoint: .bottomTrailing)

            // 旋轉光芒層(rayRotate conic 微光,僅前景卡)
            if isForeground && !reduceMotion {
                CardBackRayLayer(tint: emblemColor)
            }

            // 內縮 7pt / 11pt 雙細線框
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(TrustCardColor.cardBackFrame, lineWidth: 1)
                .padding(7)
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(TrustCardColor.cardBackFrame.opacity(0.45), lineWidth: 0.75)
                .padding(11)

            // 四角 26pt L 形金屬角飾
            CornerOrnaments(color: TrustCardColor.packTrim, size: 26, inset: 13)

            // 中央徽記 + 卡名
            VStack(spacing: 0) {
                Spacer()

                ZStack {
                    // 45° 菱形幾何線框 ×2
                    Rectangle()
                        .strokeBorder(TrustCardColor.cardBackFrame.opacity(0.4), lineWidth: 0.8)
                        .frame(width: 116, height: 116)
                        .rotationEffect(.degrees(45))
                    Rectangle()
                        .strokeBorder(TrustCardColor.cardBackFrame.opacity(0.25), lineWidth: 0.8)
                        .frame(width: 138, height: 138)
                        .rotationEffect(.degrees(45))

                    // 呼吸光暈(emblemPulse 2.6s)
                    Circle()
                        .fill(
                            RadialGradient(colors: [emblemColor.opacity(0.35), .clear],
                                           center: .center, startRadius: 8, endRadius: 76)
                        )
                        .frame(width: 150, height: 150)
                        .scaleEffect(emblemPulsing && !reduceMotion ? 1.12 : 1.0)
                        .opacity(emblemPulsing || reduceMotion ? 0.95 : 0.6)

                    // 84pt 圓形紋章:雙圈細框 + 單字大字
                    Circle()
                        .strokeBorder(emblemColor.opacity(0.75), lineWidth: 1.5)
                        .frame(width: 84, height: 84)
                    Circle()
                        .strokeBorder(emblemColor.opacity(0.4), lineWidth: 0.8)
                        .frame(width: 72, height: 72)
                    Text(kind.emblemGlyph)
                        .font(.system(size: 34, weight: .heavy, design: .serif))
                        .foregroundColor(emblemColor)
                        .shadow(color: emblemColor.opacity(0.85), radius: 9)
                }
                .frame(height: 160)

                // 卡名 + 飾線夾副標 + 羅馬序號
                Text(kind.title)
                    .font(.system(size: 24, weight: .heavy, design: .serif))
                    .kerning(7)
                    .foregroundColor(emblemColor)
                    .shadow(color: emblemColor.opacity(0.55), radius: 7)
                    .padding(.top, 18)
                    .padding(.leading, 7)   // 抵銷 kerning 尾端空隙,維持置中

                HStack(spacing: 8) {
                    ornamentLine
                    Text(kind.backSubtitle)
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .kerning(2)
                        .foregroundColor(emblemColor.opacity(0.7))
                    ornamentLine
                }
                .padding(.top, 10)

                Text(kind.romanNumeral)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(emblemColor.opacity(0.55))
                    .padding(.top, 8)

                Spacer()

                if isForeground {
                    Text("點擊翻牌")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .kerning(1.5)
                        .foregroundColor(emblemColor.opacity(0.55))
                        .padding(.bottom, 14)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        // 雙層金屬細框(外 3.5 暗金 + 內 2 亮金)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(TrustCardColor.packTrimDark, lineWidth: 3.5)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(TrustCardColor.packTrim, lineWidth: 2)
                .padding(1.5)
        )
        .modifier(ConditionalShimmer(enabled: isForeground && !reduceMotion))
        // 閃卡預告:外緣金色光暈爆發(flashBurst 2.2s 呼吸)
        .background {
            if showsFlashHint {
                Ellipse()
                    .fill(TrustCardColor.flashAura)
                    .blur(radius: 10)
                    .padding(-26)
                    .opacity(flashPulsing || reduceMotion ? 0.9 : 0.45)
                    .scaleEffect(flashPulsing && !reduceMotion ? 1.04 : 0.98)
            }
        }
        .overlay(alignment: .topTrailing) {
            if showsFlashHint {
                Text("✦ 內有閃卡")
                    .font(.system(size: 10.5, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(
                        LinearGradient(colors: TrustCardColor.flashcardTag,
                                       startPoint: .leading, endPoint: .trailing)
                    )
                    .clipShape(Capsule())
                    .shadow(color: TrustCardColor.flashAura, radius: 8)
                    .offset(x: 8, y: -9)
            }
        }
        .onAppear {
            guard !reduceMotion else { return }
            if isForeground {
                withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) {
                    emblemPulsing = true
                }
            }
            if showsFlashHint {
                withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
                    flashPulsing = true
                }
            }
        }
    }

    private var ornamentLine: some View {
        Rectangle()
            .fill(emblemColor.opacity(0.4))
            .frame(width: 26, height: 0.8)
    }
}

/// 卡背旋轉光芒層:conic 金/主色微光,14s linear 循環
private struct CardBackRayLayer: View {
    let tint: Color
    @State private var rotating = false

    var body: some View {
        GeometryReader { geo in
            AngularGradient(
                colors: [TrustCardColor.packTrim.opacity(0.14), .clear,
                         tint.opacity(0.10), .clear,
                         TrustCardColor.packTrim.opacity(0.14), .clear,
                         tint.opacity(0.10), .clear,
                         TrustCardColor.packTrim.opacity(0.14)],
                center: .center
            )
            .frame(width: geo.size.height * 1.7, height: geo.size.height * 1.7)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
            .rotationEffect(.degrees(rotating ? 360 : 0))
            .animation(.linear(duration: 14).repeatForever(autoreverses: false),
                       value: rotating)
        }
        .allowsHitTesting(false)
        .onAppear { rotating = true }
    }
}

/// 四角 L 形角飾(TCG 卡框裝飾;封面卡與卡背共用)
struct CornerOrnaments: View {
    let color: Color
    var size: CGFloat = 26
    var inset: CGFloat = 13
    var lineWidth: CGFloat = 1.5
    /// 只畫底部兩角(封面卡用)
    var bottomOnly = false

    var body: some View {
        GeometryReader { geo in
            let positions: [(x: CGFloat, y: CGFloat, angle: Double)] = bottomOnly
                ? [(inset, geo.size.height - inset - size, 270),
                   (geo.size.width - inset - size, geo.size.height - inset - size, 180)]
                : [(inset, inset, 0),
                   (geo.size.width - inset - size, inset, 90),
                   (geo.size.width - inset - size, geo.size.height - inset - size, 180),
                   (inset, geo.size.height - inset - size, 270)]
            ForEach(Array(positions.enumerated()), id: \.offset) { _, p in
                CornerL()
                    .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .frame(width: size, height: size)
                    .rotationEffect(.degrees(p.angle))
                    .offset(x: p.x, y: p.y)
            }
        }
        .allowsHitTesting(false)
    }
}

/// L 形線段(左上角基準,依旋轉擺四角)
private struct CornerL: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: rect.height))
        path.addLine(to: .zero)
        path.addLine(to: CGPoint(x: rect.width, y: 0))
        return path
    }
}
