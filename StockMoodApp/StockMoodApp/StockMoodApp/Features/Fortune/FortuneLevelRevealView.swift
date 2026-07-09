import SwiftUI

// MARK: - 13a/13b · 綜合籤等整頁儀式
// 金光(大吉滿版爆閃 → 小吉微光)/ 黑煙(大凶濃煙滿版 → 小凶輕煙),
// 強度隨六級變化;CTA「看今日籤詩」進 12c。
struct FortuneLevelRevealView: View {
    let fortune: FortuneResult
    let onContinue: () -> Void

    private var level: FortuneLevel { fortune.overallLevel }

    var body: some View {
        ZStack {
            if level.isAuspicious {
                GoldCeremonyBackground(intensity: level.revealIntensity)
            } else {
                SmokeCeremonyBackground(intensity: -level.revealIntensity)
            }

            VStack(spacing: 0) {
                Text("綜 合 籤 等")
                    .font(.system(size: 15, weight: .bold, design: .serif))
                    .kerning(6)
                    .foregroundColor(level.isAuspicious ? Color(hex: "FFF1C8") : Color(hex: "C7CCC9"))
                    .shadow(color: Color.black.opacity(0.45), radius: 3, x: 0, y: 1)
                    .padding(.top, 96)

                Spacer()

                // 籤等大字(96pt serif,金光/黑煙各自的光影)
                Text(level.label)
                    .font(.system(size: 96, weight: .black, design: .serif))
                    .kerning(10)
                    .foregroundColor(level.isAuspicious ? Color(hex: "7A5510") : Color(hex: "5E6562"))
                    .shadow(color: level.isAuspicious ? Color(hex: "FFF6D2") : Color.black.opacity(0.6),
                            radius: level.isAuspicious ? 24 : 20, x: 0, y: level.isAuspicious ? 0 : 2)
                    .shadow(color: level.isAuspicious ? Color(hex: "FFD66E").opacity(0.9) : .clear,
                            radius: 60)

                Text(fortune.levelNote)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .kerning(2)
                    .foregroundColor(level.isAuspicious ? Color(hex: "FFF6DA") : Color(hex: "C7CCC9"))
                    .shadow(color: Color.black.opacity(0.5), radius: 3, x: 0, y: 1)
                    .padding(.top, 22)

                Text(holdingsSubtitle)
                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(level.isAuspicious ? Color(hex: "F3DFA6") : Color(hex: "9AA09D"))
                    .shadow(color: Color.black.opacity(0.4), radius: 2, x: 0, y: 1)
                    .padding(.top, 12)

                Spacer()

                // CTA 看今日籤詩(13a 暖黃 / 13b 半透明白)
                Button {
                    HapticManager.shared.triggerImpact(style: .light)
                    onContinue()
                } label: {
                    Text("看今日籤詩")
                        .font(.system(size: 16, weight: level.isAuspicious ? .heavy : .bold, design: .rounded))
                        .foregroundColor(level.isAuspicious ? Color(hex: "7A5510") : Color(hex: "C7CCC9"))
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(
                            level.isAuspicious
                                ? AnyView(Color(hex: "FFF4CD").opacity(0.92))
                                : AnyView(Color.white.opacity(0.1))
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(Color.white.opacity(level.isAuspicious ? 0 : 0.14), lineWidth: 1)
                        )
                        .shadow(color: level.isAuspicious ? Color(hex: "FFD66E").opacity(0.5) : .clear,
                                radius: 15, x: 0, y: 10)
                }
                .buttonStyle(PressScaleButtonStyle())
                .padding(.horizontal, 28)
                .padding(.bottom, 24)
            }
        }
        // 背景滿版,但內容尊重底部 safe area,CTA 不會被浮動 tab bar 蓋住
        .ignoresSafeArea(edges: .top)
    }

    private var holdingsSubtitle: String {
        let total = fortune.holdings.count
        guard total > 0 else { return "依今日市場氛圍求得" }
        let up = fortune.holdings.filter { $0.level.isAuspicious }.count
        return "\(total) 檔中 \(up) 檔偏多 · \(level.levelHint)"
    }
}

// MARK: - 13a · 金光背景(暗金底 + 旋轉光苒 + 呼吸光暈;大吉外加爆閃)
struct GoldCeremonyBackground: View {
    let intensity: Int   // 1 小吉 / 2 吉 / 3 大吉
    @State private var spinning = false
    @State private var pulsing = false
    @State private var flashed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            // 暗金底(canvas:radial #6E5410 → #2A2008 55% → #140F04)
            RadialGradient(
                colors: [Color(hex: "6E5410"), Color(hex: "2A2008"), Color(hex: "140F04")],
                center: UnitPoint(x: 0.5, y: 0.4), startRadius: 0, endRadius: 620
            )
            .ignoresSafeArea()

            // 旋轉光苒(強度越高,光束越多越亮)
            RaysShape(rayCount: intensity >= 3 ? 18 : (intensity == 2 ? 12 : 8))
                .fill(Color(hex: "FFE08C").opacity(0.25 + 0.20 * Double(intensity)))
                .frame(width: 900, height: 900)
                .mask(
                    RadialGradient(
                        colors: [.black, .black, .clear],
                        center: .center, startRadius: 0, endRadius: 300
                    )
                )
                .rotationEffect(.degrees(spinning && !reduceMotion ? 360 : 0))
                .animation(.linear(duration: 14).repeatForever(autoreverses: false), value: spinning)
                .position(x: UIScreen.main.bounds.width / 2,
                          y: UIScreen.main.bounds.height * 0.4)

            // 呼吸光暈(glowPulse 1.6s)
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(hex: "FFECAA").opacity(0.6 + 0.12 * Double(intensity)),
                            Color(hex: "FFCE5C").opacity(0.35),
                            .clear,
                        ],
                        center: .center, startRadius: 10, endRadius: 260
                    )
                )
                .frame(width: 520, height: 520)
                .scaleEffect(pulsing && !reduceMotion ? 1.08 : 0.94)
                .animation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true), value: pulsing)
                .position(x: UIScreen.main.bounds.width / 2,
                          y: UIScreen.main.bounds.height * 0.4)

            // 13a 大吉「閃瞎眼」:進場全螢幕白光爆閃一次
            if intensity >= 3 {
                RadialGradient(
                    colors: [Color(hex: "FFFDF4"), Color(hex: "FFF7D6").opacity(0.7), .clear],
                    center: UnitPoint(x: 0.5, y: 0.4), startRadius: 0, endRadius: 500
                )
                .ignoresSafeArea()
                .opacity(flashed || reduceMotion ? 0 : 1)
                .animation(.easeOut(duration: 0.9), value: flashed)
            }
        }
        .onAppear {
            spinning = true
            pulsing = true
            flashed = true
        }
    }
}

// MARK: - 13b · 黑煙背景(暗夜底 + 多層煙團往上翻騰;強度越高煙越濃)
struct SmokeCeremonyBackground: View {
    let intensity: Int   // 1 小凶 / 2 凶 / 3 大凶
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            // 暗夜底(canvas:radial #2E3230 → #1A1D1B 60% → #0E100F)
            RadialGradient(
                colors: [Color(hex: "2E3230"), Color(hex: "1A1D1B"), Color(hex: "0E100F")],
                center: UnitPoint(x: 0.5, y: 0.62), startRadius: 0, endRadius: 620
            )
            .ignoresSafeArea()

            // 煙團:自畫面下緣持續往上湧(smokeUp;不閃爍、緩慢)
            if !reduceMotion {
                ForEach(0..<(2 + intensity * 2), id: \.self) { index in
                    SmokePuff(
                        size: 54 + CGFloat((index * 7) % 22),
                        xOffset: CGFloat([-30, -52, 2, -70, 24, 46, -8, 60][index % 8]),
                        duration: 2.8 + Double(index % 5) * 0.2,
                        delay: Double(index) * 0.4,
                        opacity: 0.5 + 0.12 * Double(intensity)
                    )
                }
            }
        }
    }
}

/// 單縷煙:從下往上、放大淡出,循環
struct SmokePuff: View {
    let size: CGFloat
    let xOffset: CGFloat
    let duration: Double
    let delay: Double
    let opacity: Double

    @State private var rising = false

    var body: some View {
        Circle()
            .fill(Color(hex: "343836").opacity(opacity))
            .frame(width: size, height: size)
            .blur(radius: 12)
            .scaleEffect(rising ? 2.6 : 0.8)
            .opacity(rising ? 0 : opacity)
            .position(x: UIScreen.main.bounds.width / 2 + xOffset,
                      y: UIScreen.main.bounds.height * (rising ? 0.30 : 0.66))
            .animation(
                .easeOut(duration: duration).delay(delay).repeatForever(autoreverses: false),
                value: rising
            )
            .onAppear { rising = true }
    }
}

// MARK: - 光苒(實心放射光束,rayspin 用)
struct RaysShape: Shape {
    var rayCount: Int = 12

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = max(rect.width, rect.height)
        let step = .pi * 2 / Double(rayCount)
        let halfBeam = step * 0.16
        for index in 0..<rayCount {
            let angle = step * Double(index)
            path.move(to: center)
            path.addLine(to: CGPoint(x: center.x + Foundation.cos(angle - halfBeam) * radius,
                                     y: center.y + Foundation.sin(angle - halfBeam) * radius))
            path.addLine(to: CGPoint(x: center.x + Foundation.cos(angle + halfBeam) * radius,
                                     y: center.y + Foundation.sin(angle + halfBeam) * radius))
            path.closeSubpath()
        }
        return path
    }
}
