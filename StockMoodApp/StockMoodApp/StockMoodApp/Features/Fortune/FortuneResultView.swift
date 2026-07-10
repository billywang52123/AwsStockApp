import SwiftUI

// MARK: - 14c/14d · 籤詩結果(深色沉浸:發光書法籤等 + 老籤紙 + 煙/光/雨特效)
// 14c 大凶紅黑系 / 14d 大吉金棕系;中間級別跟隨吉凶方向,特效強度隨籤等遞增。
struct FortuneResultView: View {
    let fortune: FortuneResult
    var onReplay: (() -> Void)? = nil

    private var theme: FortuneTheme { FortuneTheme(level: fortune.overallLevel) }
    private var intensity: Int { abs(fortune.overallLevel.revealIntensity) }   // 1–3

    var body: some View {
        ZStack {
            // 深色底(radial 由上而下)
            RadialGradient(
                colors: [theme.bgInner, theme.bgMid, theme.bgOuter],
                center: UnitPoint(x: 0.5, y: 0.2), startRadius: 0, endRadius: 700
            )
            .ignoresSafeArea()

            // 滴黑雨/滴金雨:只在大凶/大吉出現(z1,在籤紙後)
            if intensity >= 3 {
                FortuneRainLayer(theme: theme)
                    .allowsHitTesting(false)
            }

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    header
                        .padding(.top, 18)

                    parchment
                        .padding(.top, 22)
                        .entrance(index: 1)

                    Text("籤詩由 AI 依你的持股與市場資訊生成\n僅供情緒陪伴與資訊參考,不構成投資建議")
                        .font(.system(size: 10.5, design: .rounded))
                        .foregroundColor(Color(hex: "7A5A52"))
                        .multilineTextAlignment(.center)
                        .lineSpacing(5)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 18)

                    // 重抽(測試用):依當下持股重新求一支籤
                    if let onReplay {
                        Button {
                            HapticManager.shared.triggerSelection()
                            onReplay()
                        } label: {
                            Text("重抽一次 (測試)")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundColor(Color(hex: "7A6748"))
                                .padding(.vertical, 8)
                                .padding(.horizontal, 14)
                                .background(Color.black.opacity(0.04))
                                .clipShape(Capsule())
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 10)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 28)
            }

            // 黑煙/金光自籤紙內緩緩漂出(z3,在籤紙前;數量隨強度)
            FortunePuffLayer(theme: theme, count: 2 + intensity)
                .allowsHitTesting(false)
        }
    }

    // ── 標題區:發光書法籤等 + 副標 ─────────────────────────────

    private var header: some View {
        VStack(spacing: 0) {
            HStack {
                Text(fortuneDateTextResult())
                    .font(.system(size: 12, design: .rounded))
                    .foregroundColor(theme.subtitleColor.opacity(0.85))
                Spacer()
                Text(fortune.sessionType.drawnNote)
                    .font(.system(size: 10.5, weight: .bold, design: .rounded))
                    .foregroundColor(theme.subtitleColor)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 10)
                    .background(Color.black.opacity(0.05))
                    .clipShape(Capsule())
            }

            // 籤等大字:104 級發光書法,後方血紅/金色光暈呼吸
            GlowingLevelTitle(text: fortune.overallLevel.label, theme: theme)
                .padding(.top, 12)

            Text("今日綜合運勢 · \(fortune.overallLevel.levelHint)")
                .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                .kerning(5)
                .foregroundColor(theme.subtitleColor)
                .padding(.top, 10)
        }
    }

    // ── 老籤紙(parchment slip:舊紙 + 雙框 + 標頭橫幅 + 三欄位) ──

    private var parchment: some View {
        VStack(spacing: 13) {
            // 標頭橫幅「安心籤 · 第N籤」
            Text("安心籤 · \(fortune.stickLabel)")
                .font(.system(size: 13, weight: .bold, design: .serif))
                .kerning(4)
                .foregroundColor(theme.bannerText)
                .padding(.vertical, 4)
                .padding(.horizontal, 18)
                .background(theme.primary)

            // 欄位一:持股與狀態
            if !fortune.holdings.isEmpty {
                sectionTitle("持股與狀態")
                VStack(spacing: 0) {
                    ForEach(Array(fortune.holdings.enumerated()), id: \.element.id) { index, holding in
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(holding.name)
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                    .foregroundColor(Color(hex: "3A2A1E"))
                                Text(holding.comment)
                                    .font(.system(size: 11, design: .rounded))
                                    .foregroundColor(Color(hex: "8A7458"))
                                    .lineLimit(2)
                            }
                            Spacer()
                            Text(holding.level.label)
                                .font(BrushFont.brush(22))
                                .foregroundColor(holding.level.paperInk(auspiciousTheme: theme.isAuspicious))
                        }
                        .padding(.vertical, 7)
                        .padding(.horizontal, 2)

                        if index < fortune.holdings.count - 1 {
                            Rectangle()
                                .fill(theme.primary.opacity(0.18))
                                .frame(height: 1)
                        }
                    }
                }

                paperDivider
            }

            // 欄位二:說明
            sectionTitle("說明")
            Text(fortune.summary)
                .font(.system(size: 13, design: .rounded))
                .foregroundColor(Color(hex: "4A3A2A"))
                .lineSpacing(8)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            // 「今天的節奏」列(設計稿的結論膠囊位;文案依禁字規則用既有 stance)
            HStack(spacing: 8) {
                Text("今天的節奏")
                    .font(.system(size: 11.5, weight: .bold, design: .rounded))
                    .foregroundColor(theme.primary)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .background(theme.primary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                Text(fortune.stance)
                    .font(.system(size: 12, weight: .heavy, design: .serif))
                    .foregroundColor(theme.bannerText)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 12)
                    .background(theme.primary)
                    .clipShape(Capsule())
                Spacer()
            }

            Text(fortune.stanceNote)
                .font(.system(size: 11.5, design: .rounded))
                .foregroundColor(Color(hex: "5A4633"))
                .lineSpacing(5)
                .frame(maxWidth: .infinity, alignment: .leading)

            paperDivider

            // 欄位三:注意事項
            sectionTitle("注意事項")
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(fortune.notices.enumerated()), id: \.offset) { _, notice in
                    HStack(alignment: .top, spacing: 8) {
                        Circle()
                            .fill(theme.bulletColor)
                            .frame(width: 5, height: 5)
                            .padding(.top, 6)
                        Text(notice)
                            .font(.system(size: 12.5, design: .rounded))
                            .foregroundColor(Color(hex: "4A3A2A"))
                            .lineSpacing(6)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.top, 14)
        .padding(.bottom, 16)
        .padding(.horizontal, 12)
        // 紅/金雙框(外 2px + 內 1px)
        .overlay(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .strokeBorder(theme.primary, lineWidth: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .strokeBorder(theme.primary.opacity(0.55), lineWidth: 1)
                .padding(4)
        )
        .padding(7)
        // 舊紙:漸層 + 兩處污漬
        .background(
            ZStack {
                LinearGradient(
                    colors: [theme.paperTop, theme.paperMid, theme.paperBottom],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                Circle()
                    .fill(theme.primary.opacity(0.05))
                    .frame(width: 120, height: 120)
                    .blur(radius: 18)
                    .offset(x: -80, y: -110)
                Circle()
                    .fill(theme.primary.opacity(0.06))
                    .frame(width: 90, height: 90)
                    .blur(radius: 16)
                    .offset(x: 95, y: 130)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .shadow(color: Color.black.opacity(0.6), radius: 20, x: 0, y: 14)
        .shadow(color: theme.isAuspicious ? Color(hex: "D6A850").opacity(0.25) : .clear,
                radius: 22)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13.5, weight: .bold, design: .serif))
            .kerning(3)
            .foregroundColor(theme.primary)
            .frame(maxWidth: .infinity)
    }

    private var paperDivider: some View {
        Rectangle()
            .fill(theme.primary.opacity(0.35))
            .frame(height: 1.5)
    }
}

private func fortuneDateTextResult() -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "zh_TW")
    formatter.dateFormat = "M 月 d 日"
    let week = ["日", "一", "二", "三", "四", "五", "六"][Calendar.current.component(.weekday, from: Date()) - 1]
    return "\(formatter.string(from: Date())) · 週\(week)"
}

// MARK: - 發光書法籤等大字(flick 明滅 + 後方 emberGlow 呼吸)

struct GlowingLevelTitle: View {
    let text: String
    let theme: FortuneTheme
    @State private var flicking = false
    @State private var glowing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Text(text)
            .font(BrushFont.brush(96))
            .kerning(8)
            .foregroundColor(theme.titleColor)
            .shadow(color: theme.titleGlowStrong, radius: flicking && !reduceMotion ? 26 : 18)
            .shadow(color: theme.titleGlowSoft, radius: flicking && !reduceMotion ? 54 : 40)
            .background(
                // emberGlow:標題後方光暈呼吸
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [theme.emberGlow, .clear],
                            center: .center, startRadius: 8, endRadius: 150
                        )
                    )
                    .frame(width: 300, height: 300)
                    .blur(radius: glowing && !reduceMotion ? 26 : 18)
                    .opacity(glowing || reduceMotion ? 1 : 0.55)
            )
            .animation(.easeInOut(duration: 3.4).repeatForever(autoreverses: true), value: flicking)
            .animation(.easeInOut(duration: 4.0).repeatForever(autoreverses: true), value: glowing)
            .onAppear {
                flicking = true
                glowing = true
            }
    }
}

// MARK: - 滴黑雨/滴金雨(大凶/大吉限定:細雨絲交錯落下)

struct FortuneRainLayer: View {
    let theme: FortuneTheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // (x 比例, 寬, 長, 時長, 延遲)
    private let streaks: [(CGFloat, CGFloat, CGFloat, Double, Double)] = [
        (0.08, 2, 110, 1.6, 0.0), (0.22, 3, 140, 1.9, 0.5),
        (0.34, 2, 100, 1.4, 1.1), (0.47, 2, 120, 2.1, 0.2),
        (0.60, 3, 150, 1.7, 0.8), (0.72, 2, 105, 2.3, 1.4),
        (0.84, 2, 130, 1.5, 0.4), (0.94, 3, 115, 2.0, 1.0),
    ]

    var body: some View {
        if reduceMotion {
            EmptyView()
        } else {
            GeometryReader { geo in
                ZStack {
                    ForEach(Array(streaks.enumerated()), id: \.offset) { _, streak in
                        RainStreak(
                            color: theme.rainColor,
                            width: streak.1, length: streak.2,
                            duration: streak.3, delay: streak.4,
                            x: geo.size.width * streak.0,
                            screenHeight: geo.size.height
                        )
                    }
                }
            }
            .ignoresSafeArea()
        }
    }
}

/// 單條雨絲:自畫面頂端落下,循環
struct RainStreak: View {
    let color: Color
    let width: CGFloat
    let length: CGFloat
    let duration: Double
    let delay: Double
    let x: CGFloat
    let screenHeight: CGFloat

    @State private var falling = false

    var body: some View {
        Rectangle()
            .fill(
                LinearGradient(colors: [.clear, color], startPoint: .top, endPoint: .bottom)
            )
            .frame(width: width, height: length)
            .position(x: x, y: falling ? screenHeight + length : -length)
            .animation(
                .linear(duration: duration).delay(delay).repeatForever(autoreverses: false),
                value: falling
            )
            .onAppear { falling = true }
    }
}

// MARK: - 黑煙/金光自籤紙內漂出(drift:放大、上飄、淡出)

struct FortunePuffLayer: View {
    let theme: FortuneTheme
    let count: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion {
            EmptyView()
        } else {
            ZStack {
                ForEach(0..<count, id: \.self) { index in
                    DriftWisp(
                        color: theme.puffColor,
                        size: 44 + CGFloat((index * 9) % 26),
                        xOffset: CGFloat([-46, 38, -8, 62, -70, 14][index % 6]),
                        duration: 7.0 + Double(index % 4) * 0.8,
                        delay: Double(index) * 1.1
                    )
                }
            }
        }
    }
}
