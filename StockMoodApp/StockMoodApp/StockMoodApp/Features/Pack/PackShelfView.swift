import SwiftUI

// MARK: - 15j · 卡包架收藏頁 `PackShelfView`
// 每檔持股一包(橫滑聚焦 peek carousel)+ 歷史卡片圖鑑;發光的包有新洞察

struct PackShelfView: View {
    @State private var shelf: PackShelf?
    @State private var focusedSymbol: String?
    @State private var hasError = false

    private let cardWidth: CGFloat = 216
    private let cardHeight: CGFloat = 300

    var body: some View {
        ZStack {
            AppColor.background.ignoresSafeArea()

            if let shelf {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        // 頁頭
                        Text("卡包架")
                            .font(.system(size: 26, weight: .heavy, design: .rounded))
                            .foregroundColor(AppColor.inkPrimary)
                        Text("\(shelf.packs.count) 檔持股 · 每檔一包")
                            .font(.system(size: 12, design: .rounded))
                            .foregroundColor(AppColor.inkQuaternary)
                            .padding(.top, 4)
                        Text("隨時可打開任一包,發光的包有新洞察")
                            .font(.system(size: 12, design: .rounded))
                            .foregroundColor(AppColor.inkTertiary)
                            .padding(.top, 2)

                        if shelf.packs.isEmpty {
                            emptyState
                        } else {
                            carousel(shelf: shelf)
                        }

                        collectionGrid(shelf: shelf)

                        DisclaimerBlock(text: "本內容為現況描述與風險提示,非投資建議")
                            .padding(.top, 26)
                            .padding(.bottom, 24)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
                }
            } else if hasError {
                VStack(spacing: 10) {
                    Text("卡包架暫時打不開")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(AppColor.inkSecondary)
                    Text("網路恢復後再試一次就好")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundColor(AppColor.inkTertiary)
                }
            } else {
                ProgressView().tint(AppColor.primary)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            do {
                let result = try await DependencyContainer.shared.packService.getShelf()
                shelf = result
                focusedSymbol = result.packs.first?.symbol
            } catch {
                hasError = true
                print("Load pack shelf failed: \(error)")
            }
        }
    }

    // ── 橫向卡片架(peek carousel:聚焦置中,相鄰縮小淡出) ──

    private func carousel(shelf: PackShelf) -> some View {
        VStack(spacing: 16) {
            GeometryReader { geo in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(shelf.packs) { pack in
                            ShelfPackCard(pack: pack)
                                .frame(width: cardWidth, height: cardHeight)
                                .id(pack.symbol)
                                .visualEffect { content, proxy in
                                    let midX = proxy.frame(in: .scrollView).midX
                                    let distance = abs(midX - geo.size.width / 2)
                                    let ratio = min(distance / (cardWidth + 14), 1)
                                    return content
                                        .scaleEffect(1 - 0.18 * ratio)
                                        .opacity(1 - 0.25 * ratio)
                                }
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.viewAligned)
                .scrollPosition(id: $focusedSymbol)
                .safeAreaPadding(.horizontal, max(0, (geo.size.width - cardWidth) / 2))
            }
            .frame(height: cardHeight + 8)
            .padding(.top, 20)
            .padding(.horizontal, -24)   // carousel 滿版出血

            // 分頁指示:當前為長條
            HStack(spacing: 6) {
                ForEach(shelf.packs) { pack in
                    Capsule()
                        .fill(pack.symbol == focusedSymbol ? AppColor.primary : AppColor.bgTrack)
                        .frame(width: pack.symbol == focusedSymbol ? 18 : 6, height: 6)
                        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: focusedSymbol)
                }
            }
            .frame(maxWidth: .infinity)

            // CTA「打開 {股名} 的卡包」→ 個股 AI 觀點詳情
            if let focused = shelf.packs.first(where: { $0.symbol == focusedSymbol }) {
                NavigationLink {
                    StockInsightDetailView(symbol: focused.symbol, name: focused.name)
                } label: {
                    Text("打開 \(focused.name) 的卡包")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(AppColor.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(PressScaleButtonStyle())
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Text("還沒有持股,卡包架空空的")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(AppColor.inkSecondary)
            Text("加入持股後,每檔都會有自己的卡包")
                .font(.system(size: 12, design: .rounded))
                .foregroundColor(AppColor.inkTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    // ── 歷史卡片圖鑑 `CardCollectionGrid` ──

    private func collectionGrid(shelf: PackShelf) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("歷史卡片圖鑑")
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .foregroundColor(AppColor.inkPrimary)
                Spacer()
                Text("已收 \(shelf.collectedCount) 張")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(AppColor.inkQuaternary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(shelf.recentCards) { card in
                        CollectionMiniCard(card: card)
                    }
                    if shelf.moreCount > 0 {
                        // 「+N」虛線佔位格:其餘收藏
                        Text("+\(shelf.moreCount)")
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundColor(AppColor.inkQuaternary)
                            .frame(width: 64, height: 88)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(AppColor.inkFaint,
                                                  style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                            )
                    }
                    if shelf.recentCards.isEmpty && shelf.moreCount == 0 {
                        Text("打開第一包後,卡片會收進這裡")
                            .font(.system(size: 12, design: .rounded))
                            .foregroundColor(AppColor.inkTertiary)
                            .padding(.vertical, 34)
                    }
                }
            }
        }
        .padding(.top, 30)
    }
}

// MARK: - 卡包架單卡(產業色系深寶石漸層封面 + 金 trim;新洞察發光)

struct ShelfPackCard: View {
    let pack: ShelfPack
    @State private var glowing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var industryColor: Color { IndustryStyle.style(for: pack.industry).color }

    /// 產業 → 深寶石漸層(半導體深靛藍 / 航運深祖母綠 / 電子深海軍藍…)
    private var gemGradient: [Color] {
        if pack.industry.contains("半導體") {
            return [Color(hex: "2E3272"), Color(hex: "1D2050"), Color(hex: "111334")]
        }
        if pack.industry.contains("航運") {
            return TrustCardColor.cardBackCommunity
        }
        if pack.industry.contains("ETF") || pack.industry.contains("指數")
            || pack.industry.contains("金融") {
            return [Color(hex: "1E3A31"), Color(hex: "12281F"), Color(hex: "0A1913")]
        }
        // 電子/IC/其他:深海軍藍
        return [Color(hex: "1C2440"), Color(hex: "121830"), Color(hex: "0A0F20")]
    }

    var body: some View {
        VStack(spacing: 0) {
            // 頂部金撕條(結構同 15a TCG 封面)
            VStack {
                Spacer()
                DashedLine()
                    .stroke(TrustCardColor.packTearStrip.opacity(0.85),
                            style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    .frame(height: 1.5)
            }
            .frame(height: 36)

            Spacer()

            VStack(spacing: 8) {
                Text(pack.industry)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .kerning(1.5)
                    .foregroundColor(TrustCardColor.packTearStrip.opacity(0.9))
                // 股名:同色系發光 text-shadow
                Text(pack.name)
                    .font(.system(size: 26, weight: .heavy, design: .serif))
                    .foregroundColor(TrustCardColor.packTitleInk)
                    .shadow(color: industryColor.opacity(0.85), radius: 9)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(pack.subtitle)
                    .font(.system(size: 12.5, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.9))
            }
            .padding(.horizontal, 14)

            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(colors: gemGradient,
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        // 1.5px 金 inset trim + 內縮金細線框
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(TrustCardColor.packTrim.opacity(0.5), lineWidth: 0.8)
                .padding(7)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(TrustCardColor.packTrim, lineWidth: 1.5)
        )
        .overlay(alignment: .topTrailing) {
            if pack.hasNewInsight {
                // 「● 新洞察」金橘漸層 pill(發光 box-shadow)
                HStack(spacing: 4) {
                    Circle().fill(Color.white).frame(width: 5, height: 5)
                    Text("新洞察")
                        .font(.system(size: 10.5, weight: .bold, design: .rounded))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(
                    LinearGradient(colors: TrustCardColor.flashcardTag,
                                   startPoint: .leading, endPoint: .trailing)
                )
                .clipShape(Capsule())
                .shadow(color: TrustCardColor.flashAura, radius: 7)
                .padding(10)
            }
        }
        // 新洞察:newGlow 呼吸光暈(2.8s 循環,兩層陰影)
        .shadow(color: pack.hasNewInsight
                ? AppColor.amberBadge.opacity(glowing ? 0.55 : 0.25)
                : Color.black.opacity(0.30),
                radius: pack.hasNewInsight && glowing ? 26 : 16, x: 0, y: 14)
        .shadow(color: pack.hasNewInsight
                ? AppColor.amberBadge.opacity(glowing ? 0.30 : 0.10) : .clear,
                radius: glowing ? 40 : 24, x: 0, y: 8)
        .animation(pack.hasNewInsight && !reduceMotion
                   ? .easeInOut(duration: 2.8).repeatForever(autoreverses: true)
                   : .default,
                   value: glowing)
        .onAppear { if pack.hasNewInsight { glowing = true } }
    }
}

// MARK: - 圖鑑小卡(64×88,依卡型上色;閃卡 conic 邊框)

struct CollectionMiniCard: View {
    let card: CollectionCard

    var body: some View {
        VStack(spacing: 6) {
            Text(icon)
                .font(.system(size: 18))
            Text(title)
                .font(.system(size: 9.5, weight: .bold, design: .rounded))
                .foregroundColor(fg)
            Text(card.dateText)
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(fg.opacity(0.6))
        }
        .frame(width: 64, height: 88)
        .background(bg)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            if card.kind == "flash" {
                FlashcardRing(cornerRadius: 10, lineWidth: 2)
            } else {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(border, lineWidth: 1)
            }
        }
    }

    private var icon: String {
        switch card.kind {
        case "flash": return "✦"
        case "inference": return "🧠"
        case "community", "companion": return "💬"
        default: return "📊"
        }
    }

    private var title: String {
        switch card.kind {
        case "flash": return "閃卡"
        case "inference": return "推論"
        case "community", "companion": return "社群"
        default: return "事實"
        }
    }

    private var bg: some ShapeStyle {
        switch card.kind {
        case "inference":
            return AnyShapeStyle(LinearGradient(colors: TrustCardColor.inferenceBg,
                                                startPoint: .top, endPoint: .bottom))
        case "community", "companion":
            return AnyShapeStyle(LinearGradient(colors: TrustCardColor.communityBg,
                                                startPoint: .top, endPoint: .bottom))
        default:
            return AnyShapeStyle(TrustCardColor.factBg)
        }
    }

    private var border: Color {
        switch card.kind {
        case "inference": return TrustCardColor.inferenceBorder
        case "community", "companion": return TrustCardColor.communityBorder
        default: return TrustCardColor.factBorder
        }
    }

    private var fg: Color {
        switch card.kind {
        case "inference": return TrustCardColor.inferenceText
        case "community", "companion": return TrustCardColor.communityText
        default: return TrustCardColor.factLabelText
        }
    }
}
