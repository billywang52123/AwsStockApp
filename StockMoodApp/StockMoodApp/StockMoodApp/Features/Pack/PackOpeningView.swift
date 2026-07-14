import SwiftUI

// MARK: - 15b–15e · 開包動畫舞台(深色模式,光效在深色下最漂亮)
// KF1 撕開 → KF2 事實卡飛出翻面 → KF3 推論卡接續 → KF4 三張攤成扇形手牌
// 全程可 tap 任一處加速;右上「跳過」直達完成態;瀏覽態(15f/g/h)也在此舞台上

struct PackOpeningStage: View {
    @ObservedObject var viewModel: DailyPackViewModel

    var body: some View {
        ZStack {
            PackDarkStage()

            if let pack = viewModel.pack {
                switch viewModel.phase {
                case .opening(let keyframe):
                    keyframeContent(pack: pack, keyframe: keyframe)
                        .allowsHitTesting(false)   // 動畫中卡片不吃點擊,tap 一律加速
                case .hand:
                    PackHandView(pack: pack, viewModel: viewModel)
                case .browsing:
                    PackBrowseView(pack: pack, viewModel: viewModel)
                default:
                    EmptyView()
                }
            }

            // 右上「跳過」pill:KF1–KF4 全程存在
            if case .opening = viewModel.phase {
                VStack {
                    HStack {
                        Spacer()
                        Button {
                            viewModel.skipOpening()
                        } label: {
                            Text("跳過")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundColor(.white.opacity(0.85))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 7)
                                .background(TrustCardColor.darkSkipPillBg)
                                .clipShape(Capsule())
                                .overlay(Capsule().strokeBorder(TrustCardColor.darkSkipPillBorder, lineWidth: 1))
                        }
                        .padding(.trailing, 20)
                        .padding(.top, 8)
                    }
                    Spacer()
                }
                .zIndex(10)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if case .opening = viewModel.phase {
                viewModel.advanceKeyframe()
            }
        }
    }

    @ViewBuilder
    private func keyframeContent(pack: DailyPack, keyframe: Int) -> some View {
        switch keyframe {
        case 1:
            PackTearKeyframe(pack: pack)
                .transition(.opacity)
        case 2:
            PackFactFlyKeyframe(pack: pack)
                .transition(.opacity)
        default:
            PackInferenceKeyframe(pack: pack)
                .transition(.opacity)
        }
    }
}

// MARK: - 深色舞台:徑向漸層 + packBloom 呼吸光暈(3.2s 循環)

struct PackDarkStage: View {
    @State private var blooming = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            RadialGradient(
                colors: TrustCardColor.darkPackBg,
                center: UnitPoint(x: 0.5, y: 0.4), startRadius: 0, endRadius: 640
            )
            .ignoresSafeArea()

            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(hex: "8B8FE0").opacity(0.30), .clear],
                        center: .center, startRadius: 10, endRadius: 240
                    )
                )
                .frame(width: 480, height: 480)
                .scaleEffect(blooming && !reduceMotion ? 1.12 : 1.0)
                .opacity(blooming || reduceMotion ? 0.95 : 0.5)
                .animation(.easeInOut(duration: 3.2).repeatForever(autoreverses: true), value: blooming)
                .position(x: UIScreen.main.bounds.width / 2,
                          y: UIScreen.main.bounds.height * 0.4)
                .allowsHitTesting(false)
        }
        .onAppear { blooming = true }
    }
}

// MARK: - KF1 · 撕開(15b):虛線區光帶橫掃 + 放射光線

struct PackTearKeyframe: View {
    let pack: DailyPack

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            PackCoverCard(pack: pack, tearing: true)
            Spacer()
            Text("正在打開今日卡包…")
                .font(.system(size: 13, design: .rounded))
                .foregroundColor(.white.opacity(0.6))
            Text("輕點任一處可加速")
                .font(.system(size: 11, design: .rounded))
                .foregroundColor(.white.opacity(0.38))
                .padding(.top, 6)
                .padding(.bottom, 70)
        }
    }
}

// MARK: - KF2 · 事實卡飛出翻面(15c):spring 彈出定位 -6°,下一張殘影等待

struct PackFactFlyKeyframe: View {
    let pack: DailyPack
    @State private var landed = false

    var body: some View {
        GeometryReader { geo in
            let cardWidth = min(geo.size.width - 88, 308)
            let cardHeight = cardWidth * 472 / 308

            ZStack {
                // 下一張卡(推論卡)殘影已就位等待
                MiniPackCard(kind: .inference, pack: pack)
                    .frame(width: cardWidth * 0.6, height: cardHeight * 0.57)
                    .opacity(0.45)
                    .offset(y: geo.size.height * 0.32)

                FactCardView(pack: pack, onChip: { _ in })
                    .frame(width: cardWidth, height: cardHeight)
                    .rotationEffect(.degrees(landed ? -6 : 4))
                    .scaleEffect(landed ? 1.0 : 0.72)
                    .offset(y: landed ? -geo.size.height * 0.04 : geo.size.height * 0.18)
                    .opacity(landed ? 1 : 0)
                    .shadow(color: .black.opacity(0.45), radius: 16, x: 0, y: 18)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.72)) { landed = true }
        }
    }
}

// MARK: - KF3 · 推論卡接續(15d):事實卡縮成已讀縮圖貼頂,推論卡飛入 +4°

struct PackInferenceKeyframe: View {
    let pack: DailyPack
    @State private var landed = false

    var body: some View {
        GeometryReader { geo in
            let cardWidth = min(geo.size.width - 88, 308)
            let cardHeight = cardWidth * 472 / 308

            VStack(spacing: 0) {
                // 事實卡已讀縮圖(150×64)
                HStack(spacing: 8) {
                    Text("事實卡 · 已讀 ✓")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(TrustCardColor.factLabelText)
                    Text(pack.totalValueText)
                        .font(.system(size: 12, weight: .heavy, design: .monospaced))
                        .foregroundColor(TrustCardColor.factNumber)
                }
                .frame(width: 150, height: 64)
                .background(TrustCardColor.factBg)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .opacity(0.8)
                .scaleEffect(0.96)
                .padding(.top, 66)

                Spacer()

                InferenceCardView(pack: pack, onChip: { _ in }, onGlossary: { _ in })
                    .frame(width: cardWidth, height: cardHeight)
                    .rotationEffect(.degrees(landed ? 4 : -2))
                    .offset(y: landed ? 0 : geo.size.height * 0.4)
                    .opacity(landed ? 1 : 0)
                    .shadow(color: .black.opacity(0.45), radius: 16, x: 0, y: 18)

                Spacer()

                Text("點一下接下一張 · 1.5 秒後自動")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundColor(.white.opacity(0.38))
                    .padding(.bottom, 54)
            }
            .frame(maxWidth: .infinity)
        }
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.74)) { landed = true }
        }
    }
}

// MARK: - KF4 / 15e · 三張攤成扇形手牌(撲克牌持牌手勢)

struct PackHandView: View {
    let pack: DailyPack
    @ObservedObject var viewModel: DailyPackViewModel
    @State private var fanned = false

    // 左推論卡 -17° / 中事實卡 0.5° / 右陪伴卡 17°;z-index 由左至右遞增
    private let layout: [(kind: PackCardKind, angle: Double, xOffset: CGFloat)] = [
        (.inference, -17, -74),
        (.fact, 0.5, 0),
        (.companion, 17, 74),
    ]

    var body: some View {
        GeometryReader { geo in
            let cardWidth: CGFloat = min(geo.size.width * 0.46, 186)
            let cardHeight = cardWidth * 270 / 186

            VStack(spacing: 0) {
                // 返回入口列
                HStack {
                    Button {
                        viewModel.backToEntry()
                    } label: {
                        Text("‹ 今日卡包")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundColor(.white.opacity(0.85))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(TrustCardColor.darkSkipPillBg)
                            .clipShape(Capsule())
                    }
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)

                Spacer()

                Text("今天的三張卡")
                    .font(.system(size: 22, weight: .heavy, design: .serif))
                    .foregroundColor(.white.opacity(0.92))
                Text(pack.dateText)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5))
                    .padding(.top, 6)

                Spacer()

                // 扇形手牌:共用錨點 50% 135%
                ZStack {
                    ForEach(Array(layout.enumerated()), id: \.offset) { index, item in
                        Button {
                            viewModel.browseCard(item.kind.rawValue)
                        } label: {
                            MiniPackCard(kind: item.kind, pack: pack)
                                .frame(width: cardWidth, height: cardHeight)
                        }
                        .buttonStyle(PressScaleButtonStyle())
                        .rotationEffect(.degrees(fanned ? item.angle : 0),
                                        anchor: UnitPoint(x: 0.5, y: 1.35))
                        .offset(x: fanned ? item.xOffset * (cardWidth / 186) : 0)
                        .zIndex(Double(index))
                        .animation(
                            .spring(response: 0.4, dampingFraction: 0.78)
                                .delay(Double(index) * 0.06),   // stagger 60ms
                            value: fanned
                        )
                    }
                }
                .frame(height: cardHeight * 1.28)

                Spacer()

                Text("點任一張放大檢視 · 進入後左右滑切換")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundColor(.white.opacity(0.5))
                    .padding(.bottom, 46)
            }
            .frame(maxWidth: .infinity)
        }
        .onAppear { fanned = true }
    }
}

// MARK: - 15f/g/h · 單卡放大瀏覽:左右滑依 1→2→3 切換 + 三點分頁指示

struct PackBrowseView: View {
    let pack: DailyPack
    @ObservedObject var viewModel: DailyPackViewModel

    var body: some View {
        VStack(spacing: 0) {
            // 返回列(‹ 今日卡包)+ 序號
            HStack {
                Button {
                    viewModel.backToHand()
                } label: {
                    Text("‹ 今日卡包")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.85))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(TrustCardColor.darkSkipPillBg)
                        .clipShape(Capsule())
                }
                Spacer()
                Text("\(viewModel.browsingIndex + 1)/3")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.6))
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)

            // 左右滑切換(0.3s easeOut + light haptic,haptic 在 VM setter)
            TabView(selection: Binding(
                get: { viewModel.browsingIndex },
                set: { viewModel.browsingIndex = $0 }
            )) {
                ForEach(PackCardKind.allCases) { kind in
                    fullCard(kind: kind)
                        .padding(.horizontal, 34)
                        .padding(.vertical, 26)
                        .tag(kind.rawValue)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeOut(duration: 0.3), value: viewModel.browsingIndex)

            // 三點分頁指示器
            HStack(spacing: 8) {
                ForEach(PackCardKind.allCases) { kind in
                    Circle()
                        .fill(kind.rawValue == viewModel.browsingIndex
                              ? AppColor.primary : Color.white.opacity(0.25))
                        .frame(width: 7, height: 7)
                }
            }
            .padding(.bottom, 40)
        }
    }

    @ViewBuilder
    private func fullCard(kind: PackCardKind) -> some View {
        switch kind {
        case .fact:
            FactCardView(pack: pack) { viewModel.activeChip = $0 }
        case .inference:
            InferenceCardView(pack: pack,
                              onChip: { viewModel.activeChip = $0 },
                              onGlossary: { viewModel.activeGlossary = $0 })
        case .companion:
            CompanionCardView(pack: pack)
        }
    }
}
