import SwiftUI

// MARK: - 每日御神籤主頁(12a 入口 / 12b 搖籤 / 13 綜合籤等 / 12c 籤詩)
struct FortuneDrawView: View {
    @StateObject private var viewModel = FortuneViewModel()

    var body: some View {
        NavigationView {
            ZStack {
                AppColor.background.edgesIgnoringSafeArea(.all)

                switch viewModel.phase {
                case .loading:
                    ProgressView("正在準備籤筒...")
                case .entry:
                    FortuneEntryView(viewModel: viewModel)
                        .transition(.opacity)
                case .shaking, .revealing:
                    FortuneShakeView(isRevealing: viewModel.phase == .revealing,
                                     fortune: viewModel.fortune)
                        .transition(.opacity)
                case .levelReveal:
                    if let fortune = viewModel.fortune {
                        FortuneLevelRevealView(fortune: fortune) {
                            viewModel.proceedToResult()
                        }
                        .transition(.opacity)
                    }
                case .result:
                    if let fortune = viewModel.fortune {
                        FortuneResultView(fortune: fortune) {
                            viewModel.replayCeremony()
                        }
                        .transition(.opacity)
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
        case .levelReveal: return 4
        case .result: return 5
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

// MARK: - 頁頭(「今日運勢籤」serif 26 + 副標)
struct FortuneHeader: View {
    let subtitle: String

    var body: some View {
        VStack(spacing: 6) {
            Text("今日運勢籤")
                .font(.system(size: 26, weight: .bold, design: .serif))
                .kerning(3)
                .foregroundColor(AppColor.inkPrimary)
            Text(subtitle)
                .font(.system(size: 13, design: .rounded))
                .foregroundColor(AppColor.inkTertiary)
        }
    }
}

// MARK: - 12a · 搖籤入口(籤筒待機微晃 rock ±2.5° 3.2s,錨點筒底)
struct FortuneEntryView: View {
    @ObservedObject var viewModel: FortuneViewModel
    @State private var rocking = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            FortuneHeader(subtitle: "\(fortuneDateText()) · 依你的持股求籤")
                .padding(.top, 24)

            Spacer()

            // 光暈背景圈 + 籤筒
            ZStack {
                Circle()
                    .fill(Color(hex: "7B7FD4").opacity(0.08))
                    .frame(width: 280, height: 280)
                Circle()
                    .fill(Color(hex: "7B7FD4").opacity(0.09))
                    .frame(width: 200, height: 200)

                FortuneTubeView()
                    .rotationEffect(.degrees(rocking && !reduceMotion ? 2.5 : -2.5),
                                    anchor: UnitPoint(x: 0.5, y: 0.92))
                    .animation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true), value: rocking)
                    .onAppear { rocking = true }
            }
            .frame(width: 300, height: 290)

            Text("搖一搖籤筒,抽出今天的安心籤\n看看持股的運勢,和該注意的事")
                .font(.system(size: 14, design: .rounded))
                .foregroundColor(AppColor.inkSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(6)
                .padding(.top, 30)

            if viewModel.hasError {
                Text(viewModel.errorMessage)
                    .font(.system(size: 12, design: .rounded))
                    .foregroundColor(AppColor.roseStrong)
                    .padding(.top, 10)
            }

            Button {
                HapticManager.shared.triggerImpact(style: .medium)
                Task { await viewModel.shakeAndDraw() }
            } label: {
                Text("開始搖籤")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(AppColor.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .shadow(color: AppColor.primary.opacity(0.3), radius: 12, x: 0, y: 10)
            }
            .buttonStyle(PressScaleButtonStyle())
            .padding(.top, 18)

            Text("每天一支 · 收盤後 14:30 更新")
                .font(.system(size: 12, design: .rounded))
                .foregroundColor(AppColor.inkFaint)
                .padding(.top, 10)

            Spacer()
        }
        .padding(.horizontal, 28)
    }
}

// MARK: - 12b · 搖籤動畫(筒身傾斜 26° + shake ±13° 0.55s;籤支彈出後光/煙從籤旁長出)
struct FortuneShakeView: View {
    let isRevealing: Bool
    let fortune: FortuneResult?
    @State private var shaking = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                FortuneHeader(subtitle: fortuneDateText())
                    .padding(.top, 24)

                Spacer()

                ZStack {
                    Circle()
                        .fill(Color(hex: "7B7FD4").opacity(0.08))
                        .frame(width: 280, height: 280)

                    // 筒 + 籤支(同一座標系,傾斜與搖動一起作用)
                    ZStack(alignment: .top) {
                        // 籤支「十四」:從筒口彈出
                        if isRevealing, let fortune {
                            FortuneStickView(numberText: stickDigits(fortune))
                                .offset(y: -64)
                                .transition(.offset(y: 90).combined(with: .opacity))
                                .zIndex(0)
                        }

                        FortuneTubeView()
                            .zIndex(1)
                    }
                    .frame(width: 160, height: 236)
                    .rotationEffect(
                        .degrees(shaking && !isRevealing && !reduceMotion ? 13 : (isRevealing ? 0 : -13)),
                        anchor: UnitPoint(x: 0.5, y: 0.78)
                    )
                    .animation(
                        isRevealing ? .spring(response: 0.5, dampingFraction: 0.8)
                                    : .easeInOut(duration: 0.275).repeatForever(autoreverses: true),
                        value: shaking
                    )
                    .rotationEffect(.degrees(isRevealing || reduceMotion ? 0 : 26))
                    .animation(.spring(response: 0.5, dampingFraction: 0.8), value: isRevealing)
                }
                .frame(width: 300, height: 320)

                Text(isRevealing ? "籤來了" : "搖籤中…")
                    .font(.system(size: 19, weight: .bold, design: .serif))
                    .kerning(4)
                    .foregroundColor(Color(hex: "4A4770"))
                    .padding(.top, 40)

                Text(isRevealing ? "正在為你展開今天的運勢" : "正在依你的持股與今日市場求籤")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundColor(AppColor.inkTertiary)
                    .padding(.top, 8)

                Spacer()
            }
            .padding(.horizontal, 28)

            // 光/煙從籤支旁慢慢長出,再籠罩整個畫面(接 13a/13b)
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

// MARK: - 籤筒(設計稿 redline:160×236,藍紫筒身 + 金領口 + 直式標籤)
struct FortuneTubeView: View {
    var body: some View {
        ZStack(alignment: .top) {
            // 筒身:漸層 160° #8589DC→#5B5FA8,R20/26
            UnevenRoundedRectangle(cornerRadii: .init(
                topLeading: 20, bottomLeading: 26, bottomTrailing: 26, topTrailing: 20
            ), style: .continuous)
            .fill(
                LinearGradient(
                    colors: [Color(hex: "8589DC"), Color(hex: "5B5FA8")],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            )
            .frame(width: 160, height: 210)
            .overlay(alignment: .bottom) {
                // 底部金色飾條
                Rectangle()
                    .fill(Color(hex: "E4B384").opacity(0.55))
                    .frame(height: 8)
                    .padding(.bottom, 20)
            }
            .shadow(color: Color(hex: "5B5FA8").opacity(0.32), radius: 25, x: 0, y: 24)
            .padding(.top, 26)

            // 領口:金色 #E4B384→#D9A264,含筒口
            UnevenRoundedRectangle(cornerRadii: .init(
                topLeading: 14, bottomLeading: 8, bottomTrailing: 8, topTrailing: 14
            ), style: .continuous)
            .fill(
                LinearGradient(
                    colors: [Color(hex: "E4B384"), Color(hex: "D9A264")],
                    startPoint: .top, endPoint: .bottom
                )
            )
            .frame(width: 144, height: 34)
            .overlay(
                // 筒口
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(hex: "8A6A3F"))
                    .frame(width: 26, height: 12)
                    .offset(y: 0)
            )
            .shadow(color: Color(hex: "786446").opacity(0.25), radius: 7, x: 0, y: 6)

            // 直式標籤「安心籤」
            VStack(spacing: 8) {
                ForEach(Array("安心籤".map(String.init).enumerated()), id: \.offset) { _, char in
                    Text(char)
                        .font(.system(size: 22, weight: .bold, design: .serif))
                        .foregroundColor(Color(hex: "4A4770"))
                }
            }
            .frame(width: 56, height: 126)
            .background(Color(hex: "FBF8F1"))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color(hex: "E4B384"), lineWidth: 1.5)
            )
            .padding(.top, 62)
        }
        .frame(width: 160, height: 236)
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
                        .font(.system(size: 10, weight: .bold, design: .serif))
                        .foregroundColor(Color(hex: "FBF8F1"))
                }
            }
            .frame(width: 18, height: 32)
            .background(
                UnevenRoundedRectangle(cornerRadii: .init(
                    topLeading: 7, bottomLeading: 0, bottomTrailing: 0, topTrailing: 7
                ))
                .fill(Color(hex: "C97F7F"))
            )

            Spacer(minLength: 0)
        }
        .frame(width: 18, height: 100)
        .background(
            UnevenRoundedRectangle(cornerRadii: .init(
                topLeading: 9, bottomLeading: 5, bottomTrailing: 5, topTrailing: 9
            ))
            .fill(Color(hex: "FBF8F1"))
        )
        .overlay(
            UnevenRoundedRectangle(cornerRadii: .init(
                topLeading: 9, bottomLeading: 5, bottomTrailing: 5, topTrailing: 9
            ))
            .strokeBorder(Color(hex: "E0D6C2"), lineWidth: 1.5)
        )
        .shadow(color: Color(hex: "2B2824").opacity(0.18), radius: 9, x: 0, y: 8)
    }
}

// MARK: - 光/煙從籤支旁長出 → 籠罩畫面(revealing 階段,約 1.8s)
struct StickBloomEffect: View {
    let level: FortuneLevel
    @State private var bloomed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 籤支約在畫面中央偏上(籤筒頂 -64 再上一截)
    private let anchor = UnitPoint(x: 0.5, y: 0.32)

    var body: some View {
        if reduceMotion {
            EmptyView()
        } else {
            GeometryReader { geo in
                let origin = CGPoint(x: geo.size.width * anchor.x,
                                     y: geo.size.height * anchor.y)
                ZStack {
                    if level.isAuspicious {
                        // 金光:從籤旁一小圈,慢慢亮開籠罩
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [
                                        Color(hex: "FFECAA").opacity(0.95),
                                        Color(hex: "FFCE5C").opacity(0.55),
                                        Color(hex: "FFE296").opacity(0.0),
                                    ],
                                    center: .center, startRadius: 4, endRadius: 220
                                )
                            )
                            .frame(width: 440, height: 440)
                            .scaleEffect(bloomed ? 4.2 : 0.12)
                            .opacity(bloomed ? 1 : 0.4)
                            .position(origin)
                    } else {
                        // 黑煙:從籤旁一縷,慢慢湧出籠罩(低飽和、不閃爍)
                        ForEach(0..<4, id: \.self) { index in
                            Circle()
                                .fill(
                                    RadialGradient(
                                        colors: [
                                            Color(hex: "2E3230").opacity(0.85),
                                            Color(hex: "1A1D1B").opacity(0.45),
                                            .clear,
                                        ],
                                        center: .center, startRadius: 4, endRadius: 160
                                    )
                                )
                                .frame(width: 320, height: 320)
                                .blur(radius: 14)
                                .scaleEffect(bloomed ? 4.0 : 0.15)
                                .opacity(bloomed ? 0.9 : 0.3)
                                .position(x: origin.x + CGFloat([0, -30, 34, -12][index]),
                                          y: origin.y + CGFloat([0, 22, 14, -18][index]))
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
