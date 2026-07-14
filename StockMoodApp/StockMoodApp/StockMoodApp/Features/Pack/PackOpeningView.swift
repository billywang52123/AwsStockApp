import SwiftUI

// MARK: - 15b–15e · 開包動畫舞台(深色模式,光效在深色下最漂亮)
// KF1 撕開 → KF2 事實卡飛出翻面 → KF3 推論卡接續 → KF4 卡疊覆蓋態(卡背朝上)
// 全程可 tap 任一處加速;右上「跳過」直達卡疊;完成態(15f/g/h)也在此舞台上

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
                case .stack:
                    PackStackView(pack: pack, viewModel: viewModel)
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

// MARK: - KF2 · 事實卡飛出翻面(15c):spring 彈出定位 -6°,下一張卡背等待

struct PackFactFlyKeyframe: View {
    let pack: DailyPack
    @State private var landed = false

    var body: some View {
        GeometryReader { geo in
            let cardWidth = min(geo.size.width - 88, 308)
            let cardHeight = cardWidth * 472 / 308

            ZStack {
                // 下一張卡(推論卡)卡背已就位等待
                CardBackFace(kind: .inference)
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

// MARK: - KF4 / 15e · 卡疊覆蓋態:三張卡背朝上收攏成疊,滑動選卡、點擊翻牌

struct PackStackView: View {
    let pack: DailyPack
    @ObservedObject var viewModel: DailyPackViewModel

    /// 前景卡點擊翻牌角度(0→90 後切到完成態)
    @State private var flipAngle: Double = 0
    @State private var isFlipping = false
    /// flipHint 待機擺動(3.6s 循環,擺幅 -24°)
    @State private var hintWobbling = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let frontWidth = min(geo.size.width * 0.55, 220)
            let frontHeight = frontWidth * 314 / 220

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

                // 卡疊 + 兩側 ‹ › 淡箭頭
                ZStack {
                    stackCards(frontWidth: frontWidth, frontHeight: frontHeight)

                    HStack {
                        arrowHint("chevron.left")
                        Spacer()
                        arrowHint("chevron.right")
                    }
                    .padding(.horizontal, 14)
                    .allowsHitTesting(false)
                }
                .frame(height: frontHeight * 1.16)

                // 分頁指示器:當前為長條(18×7)
                HStack(spacing: 7) {
                    ForEach(PackCardKind.allCases) { kind in
                        Capsule()
                            .fill(kind.rawValue == viewModel.stackFront
                                  ? Color.white.opacity(0.9) : Color.white.opacity(0.28))
                            .frame(width: kind.rawValue == viewModel.stackFront ? 18 : 7, height: 7)
                            .animation(.spring(response: 0.3, dampingFraction: 0.8),
                                       value: viewModel.stackFront)
                    }
                }
                .padding(.top, 22)

                Spacer()

                Text("左右滑選卡 · 點擊翻牌")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundColor(.white.opacity(0.5))
                    .padding(.bottom, 46)
            }
            .frame(maxWidth: .infinity)
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 24)
                .onEnded { value in
                    guard !isFlipping else { return }
                    if value.translation.width < -40 {
                        viewModel.rotateStack(1)
                    } else if value.translation.width > 40 {
                        viewModel.rotateStack(-1)
                    }
                }
        )
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                hintWobbling = true
            }
        }
    }

    /// 三張卡背:前景 220×314 置中;後方兩張 scale 0.92、opacity 0.85、±44pt、∓6°
    private func stackCards(frontWidth: CGFloat, frontHeight: CGFloat) -> some View {
        ZStack {
            ForEach(PackCardKind.allCases) { kind in
                let slot = ((kind.rawValue - viewModel.stackFront) % 3 + 3) % 3
                let isFront = slot == 0
                // slot 1 = 右後方(+44, -6°)、slot 2 = 左後方(−44, +6°)
                let xOffset: CGFloat = isFront ? 0 : (slot == 1 ? 44 : -44)
                let rotation: Double = isFront ? 0 : (slot == 1 ? -6 : 6)

                CardBackFace(
                    kind: kind,
                    isForeground: isFront,
                    showsFlashHint: isFront && kind == .fact && pack.fact.flashcard != nil
                )
                .frame(width: frontWidth, height: frontHeight)
                .scaleEffect(isFront ? 1.0 : 0.92)
                .opacity(isFront ? 1.0 : 0.85)
                .rotationEffect(.degrees(rotation))
                .offset(x: xOffset * (frontWidth / 220))
                // 前景卡:flipHint 待機擺動 + 點擊翻牌(perspective 1100pt ≈ 0.5)
                .rotation3DEffect(
                    .degrees(isFront ? (isFlipping ? flipAngle : (hintWobbling ? -24 : 0)) : 0),
                    axis: (x: 0, y: 1, z: 0),
                    perspective: 0.5
                )
                .zIndex(isFront ? 2 : (slot == 1 ? 1 : 0))
                .shadow(color: .black.opacity(isFront ? 0.45 : 0.25),
                        radius: isFront ? 18 : 10, x: 0, y: isFront ? 16 : 8)
                .onTapGesture {
                    if isFront {
                        flipFrontCard()
                    } else {
                        viewModel.rotateStack(slot == 1 ? 1 : -1)
                    }
                }
                .animation(.spring(response: 0.45, dampingFraction: 0.8),
                           value: viewModel.stackFront)
            }
        }
    }

    /// 點擊翻牌:rotateY 0→90(0.25s easeIn)→ 切到完成態由 FlipRevealCard 接 −90→0
    private func flipFrontCard() {
        guard !isFlipping else { return }
        if reduceMotion {
            viewModel.revealFrontCard()
            return
        }
        isFlipping = true
        flipAngle = 0
        withAnimation(.easeIn(duration: 0.25)) { flipAngle = 90 }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.25))
            viewModel.revealFrontCard()
        }
    }

    private func arrowHint(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 17, weight: .semibold))
            .foregroundColor(.white.opacity(0.35))
    }
}

// MARK: - 15f/g/h · 完成態:左右滑依 1↔2↔3 切換 + 三點分頁指示
// 滑向未翻開的卡先播翻牌動畫再顯示內容;已翻開的卡直接切換

struct PackBrowseView: View {
    let pack: DailyPack
    @ObservedObject var viewModel: DailyPackViewModel
    @State private var shareKind: PackCardKind?

    var body: some View {
        VStack(spacing: 0) {
            // 返回列(‹ 今日卡包)+ 序號
            HStack {
                Button {
                    viewModel.backToStack()
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
                    FlipRevealCard(
                        isAlreadyRevealed: viewModel.flippedKinds.contains(kind.rawValue),
                        isFlash: kind == .fact && pack.fact.flashcard != nil,
                        onReveal: { viewModel.markFlipped(kind.rawValue) }
                    ) {
                        fullCard(kind: kind)
                    } back: {
                        CardBackFace(kind: kind, isForeground: false)
                    }
                    .padding(.horizontal, 34)
                    .padding(.vertical, 26)
                    .tag(kind.rawValue)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeOut(duration: 0.3), value: viewModel.browsingIndex)

            Button {
                shareKind = PackCardKind(rawValue: viewModel.browsingIndex)
                HapticManager.shared.triggerImpact(style: .light)
            } label: {
                Label("分享這張卡", systemImage: "square.and.arrow.up")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.92))
                    .frame(height: 42)
                    .padding(.horizontal, 18)
                    .background(TrustCardColor.darkSkipPillBg)
                    .clipShape(Capsule())
                    .overlay(Capsule().strokeBorder(TrustCardColor.darkSkipPillBorder, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityHint("製作不含個人金額的分享卡圖片")
            .sheet(item: $shareKind) { selectedKind in
                ShareCardSheet(pack: pack, kind: selectedKind)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }

            // 三點分頁指示器(社群卡當前色 communityLabelBg)
            HStack(spacing: 8) {
                ForEach(PackCardKind.allCases) { kind in
                    Circle()
                        .fill(indicatorColor(for: kind))
                        .frame(width: 7, height: 7)
                }
            }
            .padding(.top, 14)
            .padding(.bottom, 26)
        }
    }

    private func indicatorColor(for kind: PackCardKind) -> Color {
        guard kind.rawValue == viewModel.browsingIndex else { return Color.white.opacity(0.25) }
        return kind == .community ? TrustCardColor.communityLabelBg : AppColor.primary
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
        case .community:
            CommunityCardView(pack: pack) { viewModel.activeChip = $0 }
        }
    }
}

// MARK: - 翻牌容器:未翻開的卡先播 −90→0 翻入(閃卡在落定瞬間金光爆開)

struct FlipRevealCard<Front: View, Back: View>: View {
    let isAlreadyRevealed: Bool
    let isFlash: Bool
    let onReveal: () -> Void
    @ViewBuilder let front: () -> Front
    @ViewBuilder let back: () -> Back

    @State private var revealed: Bool
    @State private var angle: Double
    @State private var burstScale: CGFloat = 1.0
    @State private var burstOpacity: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(isAlreadyRevealed: Bool, isFlash: Bool, onReveal: @escaping () -> Void,
         @ViewBuilder front: @escaping () -> Front, @ViewBuilder back: @escaping () -> Back) {
        self.isAlreadyRevealed = isAlreadyRevealed
        self.isFlash = isFlash
        self.onReveal = onReveal
        self.front = front
        self.back = back
        _revealed = State(initialValue: isAlreadyRevealed)
        _angle = State(initialValue: isAlreadyRevealed ? 0 : -90)
    }

    var body: some View {
        ZStack {
            // 閃卡翻至正面瞬間:光暈 scale 1→1.6 爆開(0.25s easeOut)
            if isFlash {
                Ellipse()
                    .fill(TrustCardColor.flashAura)
                    .blur(radius: 12)
                    .padding(-20)
                    .scaleEffect(burstScale)
                    .opacity(burstOpacity)
                    .allowsHitTesting(false)
            }

            if revealed {
                front()
                    .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
            } else {
                back()
            }
        }
        .onAppear {
            guard !revealed else { return }
            if reduceMotion {
                revealed = true
                angle = 0
                onReveal()
                return
            }
            // 進場即翻:卡背停半拍 → 翻入正面
            revealed = true
            angle = -90
            withAnimation(.easeOut(duration: 0.25).delay(0.05)) { angle = 0 }
            if isFlash {
                burstOpacity = 0.9
                burstScale = 1.0
                withAnimation(.easeOut(duration: 0.25).delay(0.2)) {
                    burstScale = 1.6
                    burstOpacity = 0
                }
            }
            onReveal()
        }
    }
}
