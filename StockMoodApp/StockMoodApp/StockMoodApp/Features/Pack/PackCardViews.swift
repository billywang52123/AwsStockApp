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

// MARK: - 15h · 陪伴卡完成態 `CompanionCard`

struct CompanionCardView: View {
    let pack: DailyPack
    private var companion: CompanionCardData { pack.companion }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                CardTagPill(text: "AI 陪伴訊息", bg: TrustCardColor.companionLabelBg)
                Spacer()
                Text("不含任何買賣暗示")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundColor(TrustCardColor.companionText.opacity(0.7))
            }
            .padding(.bottom, 18)

            ScrollView(showsIndicators: false) {
                // 正文:LXGW WenKai TC 手寫感,行高 2.05
                Text(companion.text)
                    .font(BrushFont.brush(20))
                    .foregroundColor(TrustCardColor.companionText)
                    .lineSpacing(21)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            HStack(alignment: .lastTextBaseline) {
                Text(companion.signature)
                    .font(BrushFont.brush(14))
                    .foregroundColor(TrustCardColor.companionText.opacity(0.85))
                Spacer()
                Text("Day \(companion.dayCount)")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(TrustCardColor.companionText.opacity(0.6))
            }
        }
        .padding(20)
        .background(
            ZStack {
                LinearGradient(colors: TrustCardColor.companionBg,
                               startPoint: .top, endPoint: .bottom)
                // 右上角 amber 光暈裝飾圓(不遮文字)
                Circle()
                    .fill(
                        RadialGradient(colors: [AppColor.amberBadge.opacity(0.35), .clear],
                                       center: .center, startRadius: 6, endRadius: 80)
                    )
                    .frame(width: 150, height: 150)
                    .offset(x: 90, y: -160)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(TrustCardColor.companionBorder, lineWidth: 1.5)
        )
        .shadow(color: Color(red: 120/255, green: 100/255, blue: 70/255).opacity(0.18),
                radius: 25, x: 0, y: 24)
    }
}

// MARK: - 手牌態迷你卡(15e 扇形;186×270 比例,尺寸由外部給)

struct MiniPackCard: View {
    let kind: PackCardKind
    let pack: DailyPack

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CardTagPill(text: kind.tagText, bg: tagBg, fg: tagFg)
            Spacer()
            Text(headline)
                .font(kind == .companion ? BrushFont.brush(17)
                      : .system(size: 17, weight: .heavy, design: kind == .fact ? .monospaced : .rounded))
                .foregroundColor(headlineColor)
                .lineSpacing(6)
                .lineLimit(4)
            Spacer()
            Text(kind.title)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundColor(headlineColor.opacity(0.55))
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(borderColor, lineWidth: isFlash ? 0 : 1.5)
        )
        .overlay { if isFlash { FlashcardRing(cornerRadius: 18, lineWidth: 2.5) } }
        .shadow(color: Color.black.opacity(0.35), radius: 14, x: 0, y: 12)
    }

    private var isFlash: Bool { kind == .fact && pack.fact.flashcard != nil }

    private var headline: String {
        switch kind {
        case .fact: return "\(pack.totalValueText)\n\(String(format: "%+.2f%%", pack.fact.totalChangePercent))"
        case .inference: return pack.inference.conclusion
        case .companion: return pack.companion.text
        }
    }

    private var cardBg: some ShapeStyle {
        switch kind {
        case .fact:
            return AnyShapeStyle(TrustCardColor.factBg)
        case .inference:
            return AnyShapeStyle(LinearGradient(colors: TrustCardColor.inferenceBg,
                                                startPoint: .top, endPoint: .bottom))
        case .companion:
            return AnyShapeStyle(LinearGradient(colors: TrustCardColor.companionBg,
                                                startPoint: .top, endPoint: .bottom))
        }
    }

    private var borderColor: Color {
        switch kind {
        case .fact: return TrustCardColor.factBorder
        case .inference: return TrustCardColor.inferenceBorder
        case .companion: return TrustCardColor.companionBorder
        }
    }

    private var tagBg: Color {
        switch kind {
        case .fact: return TrustCardColor.factLabelBg
        case .inference: return TrustCardColor.inferenceLabelBg
        case .companion: return TrustCardColor.companionLabelBg
        }
    }

    private var tagFg: Color {
        kind == .fact ? TrustCardColor.factLabelText : .white
    }

    private var headlineColor: Color {
        switch kind {
        case .fact: return TrustCardColor.factNumber
        case .inference: return TrustCardColor.inferenceText
        case .companion: return TrustCardColor.companionText
        }
    }
}
