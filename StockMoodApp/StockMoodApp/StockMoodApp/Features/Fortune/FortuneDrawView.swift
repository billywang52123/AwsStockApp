import SwiftUI

// MARK: - 每日御神籤主頁(14a 入口 / 14b 搖籤 / 14c·14d 籤詩結果)
// 第十二輪最終方向:暗場沉浸 · 老籤紙 · 發光書法 · 煙/光自籤內漂出
struct FortuneDrawView: View {
    @StateObject private var viewModel = FortuneViewModel()

    var body: some View {
        NavigationView {
            ZStack {
                // 全程深色暗場,避免階段切換時閃白
                Color(hex: "0C0805").ignoresSafeArea()

                switch viewModel.phase {
                case .loading:
                    ProgressView("正在準備籤筒...")
                        .tint(Color(hex: "C99A4A"))
                        .foregroundColor(Color(hex: "B7A57E"))
                case .entry:
                    FortuneEntryView(viewModel: viewModel)
                        .transition(.opacity)
                case .shaking, .revealing:
                    FortuneShakeView(isRevealing: viewModel.phase == .revealing,
                                     fortune: viewModel.fortune)
                        .transition(.opacity)
                case .result:
                    if let fortune = viewModel.fortune {
                        FortuneResultView(fortune: fortune) {
                            viewModel.replayCeremony()
                        }
                        // 淡入 + 上移展開籤詩(README 抽籤流程)
                        .transition(.opacity.combined(with: .offset(y: 26)))
                    }
                }
            }
            .animation(.easeInOut(duration: 0.5), value: phaseKey)
            .navigationBarHidden(true)
            .task { await viewModel.loadToday() }
        }
    }

    private var phaseKey: Int {
        switch viewModel.phase {
        case .loading: return 0
        case .entry: return 1
        case .shaking: return 2
        case .revealing: return 3
        case .result: return 4
        }
    }
}

// MARK: - 日期字串(「7 月 9 日 · 週四」)
func fortuneDateText() -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "zh_TW")
    formatter.dateFormat = "M 月 d 日"
    let week = ["日", "一", "二", "三", "四", "五", "六"][Calendar.current.component(.weekday, from: Date()) - 1]
    return "\(formatter.string(from: Date())) · 週\(week)"
}

// MARK: - 暗場背景(14a/14b:琥珀暗場 + 呼吸光暈)

struct FortuneDarkStage: View {
    @State private var glowing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            RadialGradient(
                colors: [Color(hex: "231A10"), Color(hex: "120C06"), Color(hex: "080503")],
                center: UnitPoint(x: 0.5, y: 0.42), startRadius: 0, endRadius: 620
            )
            .ignoresSafeArea()

            // emberGlow:中央琥珀色光暈呼吸(4.5s)
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(hex: "C99A4A").opacity(0.22), .clear],
                        center: .center, startRadius: 10, endRadius: 230
                    )
                )
                .frame(width: 460, height: 460)
                .blur(radius: glowing ? 26 : 18)
                .opacity(glowing || reduceMotion ? 1.0 : 0.55)
                .animation(.easeInOut(duration: 4.5).repeatForever(autoreverses: true), value: glowing)
                .position(x: UIScreen.main.bounds.width / 2,
                          y: UIScreen.main.bounds.height * 0.42)
        }
        .onAppear { glowing = true }
    }
}

/// 一縷微光/煙氣:自下往上漂散(drift),入口與搖籤共用
struct DriftWisp: View {
    let color: Color
    let size: CGFloat
    let xOffset: CGFloat
    let duration: Double
    let delay: Double

    @State private var rising = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .blur(radius: 12)
            .scaleEffect(rising ? 2.1 : 0.5)
            .opacity(rising ? 0 : 0.5)
            .position(x: UIScreen.main.bounds.width / 2 + xOffset,
                      y: UIScreen.main.bounds.height * (rising ? 0.18 : 0.52))
            .animation(
                .easeIn(duration: duration).delay(delay).repeatForever(autoreverses: false),
                value: rising
            )
            .onAppear { rising = true }
    }
}

// MARK: - 14a · 求籤入口(暗場 + 暗紅籤筒 + 金 CTA)

struct FortuneEntryView: View {
    @ObservedObject var viewModel: FortuneViewModel
    @State private var rocking = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            FortuneDarkStage()

            if !reduceMotion {
                DriftWisp(color: Color(hex: "E9C77E").opacity(0.35), size: 46,
                          xOffset: -60, duration: 7.5, delay: 0)
                DriftWisp(color: Color(hex: "C99A4A").opacity(0.3), size: 38,
                          xOffset: 52, duration: 8.5, delay: 2.4)
            }

            VStack(spacing: 0) {
                // 標題「今日求籤」:發光書法(毛筆楷書 40 金色光暈)
                Text("今日求籤")
                    .font(BrushFont.brush(40))
                    .kerning(8)
                    .foregroundColor(Color(hex: "E9C77E"))
                    .shadow(color: Color(hex: "E9C77E").opacity(0.55), radius: 14)
                    .shadow(color: Color(hex: "A9772F").opacity(0.4), radius: 30)
                    .padding(.top, 30)

                Text("\(fortuneDateText()) · 依你的持股問運勢")
                    .font(.system(size: 12.5, design: .rounded))
                    .foregroundColor(Color(hex: "9C8A66"))
                    .padding(.top, 10)

                Spacer()

                OmikujiTubeView()
                    .rotationEffect(.degrees(rocking && !reduceMotion ? 2.5 : -2.5),
                                    anchor: UnitPoint(x: 0.5, y: 0.92))
                    .animation(.easeInOut(duration: 1.7).repeatForever(autoreverses: true), value: rocking)
                    .onAppear { rocking = true }

                Text("誠心搖動籤筒\n抽出今日持股的吉凶籤詩")
                    .font(.system(size: 13.5, design: .rounded))
                    .foregroundColor(Color(hex: "B7A57E"))
                    .multilineTextAlignment(.center)
                    .lineSpacing(8)
                    .padding(.top, 28)

                if viewModel.hasError {
                    Text(viewModel.errorMessage)
                        .font(.system(size: 12, design: .rounded))
                        .foregroundColor(Color(hex: "D6301F"))
                        .padding(.top, 10)
                }

                Spacer()

                // 主 CTA「搖 籤 問 卜」:金色漸層
                Button {
                    HapticManager.shared.triggerImpact(style: .medium)
                    Task { await viewModel.shakeAndDraw() }
                } label: {
                    Text("搖 籤 問 卜")
                        .font(.system(size: 17, weight: .heavy, design: .serif))
                        .kerning(3)
                        .foregroundColor(Color(hex: "2A1908"))
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(
                            LinearGradient(
                                colors: [Color(hex: "C99A4A"), Color(hex: "A2762E")],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .shadow(color: Color(hex: "96641E").opacity(0.4), radius: 13, x: 0, y: 12)
                }
                .buttonStyle(PressScaleButtonStyle())

                Text("每日一籤 · 收盤後 14:30 更新")
                    .font(.system(size: 11.5, design: .rounded))
                    .foregroundColor(Color(hex: "7C6C4E"))
                    .padding(.top, 12)
                    .padding(.bottom, 8)
            }
            .padding(.horizontal, 28)
        }
    }
}

// MARK: - 14b · 搖籤中(筒身傾斜 24° + 高頻搖動;籤支彈出後光/煙長出)

struct FortuneShakeView: View {
    let isRevealing: Bool
    let fortune: FortuneResult?
    @State private var shaking = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            FortuneDarkStage()

            // 灰白煙氣自筒口向上漂散
            if !reduceMotion {
                DriftWisp(color: Color(hex: "D8CBB2").opacity(0.28), size: 40,
                          xOffset: -18, duration: 6.0, delay: 0)
                DriftWisp(color: Color(hex: "CFC2A8").opacity(0.22), size: 32,
                          xOffset: 30, duration: 7.2, delay: 1.6)
                DriftWisp(color: Color(hex: "E4D8BE").opacity(0.18), size: 26,
                          xOffset: 0, duration: 8.0, delay: 3.0)
            }

            VStack(spacing: 0) {
                Text(isRevealing ? "籤來了" : "搖籤中…")
                    .font(BrushFont.brush(30))
                    .kerning(6)
                    .foregroundColor(Color(hex: "E4C079"))
                    .shadow(color: Color(hex: "E4C079").opacity(0.55), radius: 12)
                    .padding(.top, 46)

                Text(isRevealing ? "正在為你展開今天的籤詩" : "正依你的持股與今日市場求卜")
                    .font(.system(size: 12.5, design: .rounded))
                    .foregroundColor(Color(hex: "9C8A66"))
                    .padding(.top, 10)

                Spacer()

                // 筒 + 籤支(同一座標系,傾斜與搖動一起作用)
                ZStack(alignment: .top) {
                    if isRevealing, let fortune {
                        FortuneStickView(numberText: stickDigits(fortune))
                            .offset(y: -62)
                            .transition(.offset(y: 90).combined(with: .opacity))
                            .zIndex(0)
                    }

                    OmikujiTubeView()
                        .zIndex(1)
                }
                .frame(width: 150, height: 230)
                .rotationEffect(
                    .degrees(shaking && !isRevealing && !reduceMotion ? 13 : (isRevealing ? 0 : -13)),
                    anchor: UnitPoint(x: 0.5, y: 0.8)
                )
                .animation(
                    isRevealing ? .spring(response: 0.5, dampingFraction: 0.8)
                                : .easeInOut(duration: 0.25).repeatForever(autoreverses: true),
                    value: shaking
                )
                .rotationEffect(.degrees(isRevealing || reduceMotion ? 0 : 24))
                .animation(.spring(response: 0.5, dampingFraction: 0.8), value: isRevealing)
                .padding(.top, 30)

                Spacer()

                FortuneLoadingDots()
                    .opacity(isRevealing ? 0 : 1)
                    .padding(.bottom, 60)
            }
            .padding(.horizontal, 28)

            // 光/煙從籤支旁慢慢長出,再籠罩整個畫面(接 14c/14d)
            if isRevealing, let fortune {
                StickBloomEffect(level: fortune.overallLevel)
                    .allowsHitTesting(false)
            }
        }
        .onAppear {
            shaking = true
            for delay in stride(from: 0.0, to: 2.2, by: 0.55) {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    HapticManager.shared.triggerImpact(style: .medium)
                }
            }
        }
    }

    private func stickDigits(_ fortune: FortuneResult) -> String {
        String(fortune.stickLabel.dropFirst().dropLast())
    }
}

/// 三顆載入點(floaty 交錯)
struct FortuneLoadingDots: View {
    @State private var bouncing = false
    private let colors = ["D6A850", "B98E3E", "8A6A2E"]

    var body: some View {
        HStack(spacing: 10) {
            ForEach(Array(colors.enumerated()), id: \.offset) { index, hex in
                Circle()
                    .fill(Color(hex: hex))
                    .frame(width: 8, height: 8)
                    .offset(y: bouncing ? -6 : 2)
                    .animation(
                        .easeInOut(duration: 0.6)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.18),
                        value: bouncing
                    )
            }
        }
        .onAppear { bouncing = true }
    }
}

// MARK: - 御神籤筒(14a redline:150×230,暗漆紅黑筒身 + 金色筒蓋 + 直式標籤)

struct OmikujiTubeView: View {
    var body: some View {
        ZStack(alignment: .top) {
            // 筒身:暗漆紅黑漸層 160°
            UnevenRoundedRectangle(cornerRadii: .init(
                topLeading: 18, bottomLeading: 24, bottomTrailing: 24, topTrailing: 18
            ), style: .continuous)
            .fill(
                LinearGradient(
                    colors: [Color(hex: "4A1712"), Color(hex: "230B08")],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            )
            .frame(width: 150, height: 204)
            .overlay(alignment: .bottom) {
                // 底部金色飾條
                Rectangle()
                    .fill(Color(hex: "CFA05A").opacity(0.5))
                    .frame(height: 7)
                    .padding(.bottom, 18)
            }
            .shadow(color: Color.black.opacity(0.55), radius: 22, x: 0, y: 20)
            .padding(.top, 26)

            // 筒蓋:金色漸層,含筒口
            UnevenRoundedRectangle(cornerRadii: .init(
                topLeading: 12, bottomLeading: 7, bottomTrailing: 7, topTrailing: 12
            ), style: .continuous)
            .fill(
                LinearGradient(
                    colors: [Color(hex: "CFA05A"), Color(hex: "A9772F")],
                    startPoint: .top, endPoint: .bottom
                )
            )
            .frame(width: 136, height: 32)
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color(hex: "5A3A14"))
                    .frame(width: 24, height: 11)
            )
            .shadow(color: Color.black.opacity(0.35), radius: 7, x: 0, y: 6)

            // 直式標籤「安心籤」:書法紅字 on 老紙
            VStack(spacing: 7) {
                ForEach(Array("安心籤".map(String.init).enumerated()), id: \.offset) { _, char in
                    Text(char)
                        .font(BrushFont.brush(21))
                        .foregroundColor(Color(hex: "7A1E14"))
                }
            }
            .frame(width: 52, height: 118)
            .background(Color(hex: "EFE3C2"))
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(Color(hex: "A9772F"), lineWidth: 1.5)
            )
            .padding(.top, 60)
        }
        .frame(width: 150, height: 230)
    }
}

// MARK: - 彈出的籤支(18×100 奶白木片,紅頭直式數字)

struct FortuneStickView: View {
    let numberText: String

    var body: some View {
        VStack(spacing: 0) {
            // 紅頭:直式白字
            VStack(spacing: 1) {
                ForEach(Array(numberText.map(String.init).enumerated()), id: \.offset) { _, char in
                    Text(char)
                        .font(BrushFont.brush(10))
                        .foregroundColor(Color(hex: "FBF8F1"))
                }
            }
            .frame(width: 18, height: 32)
            .background(
                UnevenRoundedRectangle(cornerRadii: .init(
                    topLeading: 7, bottomLeading: 0, bottomTrailing: 0, topTrailing: 7
                ))
                .fill(Color(hex: "7A1E14"))
            )

            Spacer(minLength: 0)
        }
        .frame(width: 18, height: 100)
        .background(
            UnevenRoundedRectangle(cornerRadii: .init(
                topLeading: 9, bottomLeading: 5, bottomTrailing: 5, topTrailing: 9
            ))
            .fill(Color(hex: "F5EBD2"))
        )
        .overlay(
            UnevenRoundedRectangle(cornerRadii: .init(
                topLeading: 9, bottomLeading: 5, bottomTrailing: 5, topTrailing: 9
            ))
            .strokeBorder(Color(hex: "D9C7A0"), lineWidth: 1.5)
        )
        .shadow(color: Color.black.opacity(0.35), radius: 9, x: 0, y: 8)
    }
}

// MARK: - 開籤瞬間:光/煙從籤支旁長出 → 籠罩畫面(revealing 階段,約 1.8s)
// 強度隨六級籤等遞增(README 特效強度階梯)

struct StickBloomEffect: View {
    let level: FortuneLevel
    @State private var bloomed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 籤支約在畫面中央偏上
    private let anchor = UnitPoint(x: 0.5, y: 0.34)

    var body: some View {
        if reduceMotion {
            EmptyView()
        } else {
            GeometryReader { geo in
                let origin = CGPoint(x: geo.size.width * anchor.x,
                                     y: geo.size.height * anchor.y)
                let intensity = abs(level.revealIntensity)   // 1–3
                ZStack {
                    if level.isAuspicious {
                        // 金光:從籤旁一小圈亮開;強度越高越亮越大
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [
                                        Color(hex: "FFECAA").opacity(0.55 + 0.15 * Double(intensity)),
                                        Color(hex: "F0C860").opacity(0.35 + 0.08 * Double(intensity)),
                                        Color(hex: "C89628").opacity(0.0),
                                    ],
                                    center: .center, startRadius: 4, endRadius: 220
                                )
                            )
                            .frame(width: 440, height: 440)
                            .scaleEffect(bloomed ? 2.6 + 0.8 * CGFloat(intensity) : 0.12)
                            .opacity(bloomed ? 1 : 0.4)
                            .position(origin)
                    } else {
                        // 黑煙:從籤旁一縷湧出;強度越高煙越多越濃
                        ForEach(0..<(1 + intensity), id: \.self) { index in
                            Circle()
                                .fill(
                                    RadialGradient(
                                        colors: [
                                            Color(hex: "1E1512").opacity(0.6 + 0.1 * Double(intensity)),
                                            Color(hex: "0E0705").opacity(0.4),
                                            .clear,
                                        ],
                                        center: .center, startRadius: 4, endRadius: 160
                                    )
                                )
                                .frame(width: 320, height: 320)
                                .blur(radius: 14)
                                .scaleEffect(bloomed ? 3.2 + 0.5 * CGFloat(intensity) : 0.15)
                                .opacity(bloomed ? 0.9 : 0.3)
                                .position(x: origin.x + CGFloat([0, -30, 34, -12][index % 4]),
                                          y: origin.y + CGFloat([0, 22, 14, -18][index % 4]))
                                .animation(.easeIn(duration: 1.7).delay(Double(index) * 0.12), value: bloomed)
                        }
                    }
                }
                .animation(.easeIn(duration: 1.7), value: bloomed)
            }
            .ignoresSafeArea()
            .onAppear { bloomed = true }
        }
    }
}
