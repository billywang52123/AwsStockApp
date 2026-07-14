import SwiftUI

// MARK: - 每日抽卡包主頁(spec 06 · 15a 入口 → 15b–15e 開包 → 15f/g/h 瀏覽)
// 取代御神籤:AI 每天把整體庫存整理成一包三張卡(事實 → 推論 → 社群,順序不可亂)

struct TodayPackView: View {
    @StateObject private var viewModel = DailyPackViewModel()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationView {
            ZStack {
                AppColor.background.ignoresSafeArea()

                switch viewModel.phase {
                case .loading:
                    ProgressView("正在整理今天的卡包…")
                        .tint(AppColor.primary)
                        .foregroundColor(AppColor.inkTertiary)
                case .entry:
                    PackEntryView(viewModel: viewModel, reduceMotion: reduceMotion)
                        .transition(.opacity)
                case .opening, .stack, .browsing:
                    PackOpeningStage(viewModel: viewModel)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.35), value: phaseKey)
            .navigationBarHidden(true)
            .task { await viewModel.loadToday() }
            // 15i 出處 chip bottom sheet(任一出處 chip 點擊觸發)
            .sheet(item: $viewModel.activeChip) { chip in
                SourceChipSheet(chip: chip) { viewModel.activeChip = nil }
            }
            // 15g 名詞小卡
            .sheet(item: $viewModel.activeGlossary) { term in
                GlossaryTermSheet(term: term) { viewModel.activeGlossary = nil }
            }
        }
    }

    private var phaseKey: Int {
        switch viewModel.phase {
        case .loading: return 0
        case .entry: return 1
        case .opening(let kf): return 10 + kf
        case .stack: return 20
        case .browsing: return 30
        }
    }
}

// MARK: - 15a · 今日卡包入口 `TodayPackEntryView`

struct PackEntryView: View {
    @ObservedObject var viewModel: DailyPackViewModel
    let reduceMotion: Bool

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                // 日期列 + 標題
                Text(viewModel.pack?.dateText ?? "")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(AppColor.inkQuaternary)
                    .padding(.top, 18)

                Text("今日卡包")
                    .font(.system(size: 30, weight: .heavy, design: .serif))
                    .foregroundColor(AppColor.inkPrimary)
                    .padding(.top, 6)

                Text("AI 把你的 \(viewModel.pack?.holdingsCount ?? 0) 檔庫存整理成一包今日分析,個股可展開細看")
                    .font(.system(size: 12.5, design: .rounded))
                    .foregroundColor(AppColor.inkTertiary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)
                    .padding(.horizontal, 32)

                // 卡包封面
                if let pack = viewModel.pack {
                    PackCoverCard(pack: pack, tearing: false)
                        .padding(.top, 22)

                    // 「今天為什麼值得看」卡
                    WhyTodayCard(whyToday: pack.whyToday) { viewModel.activeChip = $0 }
                        .padding(.top, 20)
                        .padding(.horizontal, 24)
                }

                if viewModel.hasError {
                    Text(viewModel.errorMessage)
                        .font(.system(size: 12, design: .rounded))
                        .foregroundColor(AppColor.roseStrong)
                        .padding(.top, 10)
                        .padding(.horizontal, 24)
                }

                // CTA「開啟今日卡包」
                Button {
                    HapticManager.shared.triggerImpact(style: .light)
                    viewModel.openPack(reduceMotion: reduceMotion)
                } label: {
                    Text(viewModel.pack?.opened == true ? "再看今日卡包" : "開啟今日卡包")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(AppColor.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .shadow(color: AppColor.primary.opacity(0.35), radius: 13, x: 0, y: 10)
                }
                .buttonStyle(PressScaleButtonStyle())
                .padding(.top, 22)
                .padding(.horizontal, 24)
                .disabled(viewModel.pack == nil)

                Text("每天一包 · 收盤後 14:30 更新")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundColor(AppColor.inkFaint)
                    .padding(.top, 10)

                // 卡包架(15j)與週末體檢(15k)入口
                HStack(spacing: 12) {
                    NavigationLink {
                        PackShelfView()
                    } label: {
                        entrySecondaryLabel(icon: "square.stack.fill", text: "卡包架")
                    }
                    NavigationLink {
                        WeeklyCheckupView()
                    } label: {
                        entrySecondaryLabel(icon: "checkmark.seal.fill", text: "週末體檢")
                    }
                }
                .padding(.top, 18)
                .padding(.horizontal, 24)

                // 邊界揭露:全頁 footer 固定顯示
                DisclaimerBlock(text: "本內容為現況描述與風險提示,非投資建議｜資料截至 \(viewModel.pack?.dataDate ?? "—")")
                    .padding(.top, 24)
                    .padding(.bottom, 28)
                    .padding(.horizontal, 24)
            }
        }
    }

    private func entrySecondaryLabel(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
            Text(text)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
        }
        .foregroundColor(AppColor.primary)
        .frame(maxWidth: .infinity)
        .frame(height: 46)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .strokeBorder(Color(hex: "E3DFD4"), lineWidth: 1.5)
        )
    }
}

// MARK: - 卡包封面 `PackCoverCard`(212×292,15a 與 KF1 共用)
// TCG 質感,與卡背同語彙:深靛藍寶石漸層 + 金箔雙層框 + 金撕條 + 光芒層 + 徽記暈

struct PackCoverCard: View {
    let pack: DailyPack
    /// KF1 撕開態:撕條光帶橫掃 + 放射光線
    let tearing: Bool

    @State private var sweeping = false
    @State private var emblemPulsing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            // 頂部「— 由此撕開 —」撕條(44 高,金箔漸層底 + dashed 金)
            ZStack {
                LinearGradient(colors: [TrustCardColor.packTearStrip.opacity(0.22), .clear],
                               startPoint: .top, endPoint: .bottom)
                VStack {
                    Spacer()
                    HStack(spacing: 8) {
                        Text("—")
                        Text("由此撕開")
                            .kerning(2)
                        Text("—")
                    }
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundColor(TrustCardColor.packTearStrip)
                    Spacer()
                    DashedLine()
                        .stroke(TrustCardColor.packTearStrip,
                                style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                        .frame(height: 1.5)
                }
                .padding(.top, 6)

                // KF1:一條全息光帶沿撕條橫掃(glowPulse)
                if tearing && !reduceMotion {
                    LinearGradient(colors: [.clear, .white.opacity(0.9), .clear],
                                   startPoint: .leading, endPoint: .trailing)
                        .frame(width: 74, height: 10)
                        .blur(radius: 4)
                        .offset(x: sweeping ? 92 : -92, y: 14)
                        .animation(.easeInOut(duration: 1.6).repeatForever(autoreverses: false),
                                   value: sweeping)
                        .onAppear { sweeping = true }
                }
            }
            .frame(height: 44)

            Spacer()

            // 內容置中
            VStack(spacing: 10) {
                Text("庫存分析 · 內含 3 張卡")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .kerning(3)
                    .foregroundColor(TrustCardColor.packTearStrip.opacity(0.9))
                    .padding(.leading, 3)   // 抵銷 kerning 尾端空隙

                // 「我的庫存」:米金大字 + 後方 110pt 紫光徽記暈 + 45° 菱形線框
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(colors: [Color(hex: "8B8FE0").opacity(0.45), .clear],
                                           center: .center, startRadius: 8, endRadius: 55)
                        )
                        .frame(width: 110, height: 110)
                        .scaleEffect(emblemPulsing && !reduceMotion ? 1.12 : 1.0)
                        .opacity(emblemPulsing || reduceMotion ? 0.95 : 0.6)
                    Rectangle()
                        .strokeBorder(TrustCardColor.packTrim.opacity(0.5), lineWidth: 0.8)
                        .frame(width: 92, height: 92)
                        .rotationEffect(.degrees(45))
                    Text("我的庫存")
                        .font(.system(size: 32, weight: .heavy, design: .serif))
                        .foregroundColor(TrustCardColor.packTitleInk)
                        .shadow(color: TrustCardColor.packTearStrip.opacity(0.65), radius: 9)
                }
                .frame(height: 104)

                Text("\(pack.holdingsCount) 檔 · \(pack.totalValueText)")
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.9))

                // 金框 pill「今日 +1.1%」
                Text(String(format: "今日 %+.1f%%", pack.fact.totalChangePercent))
                    .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                    .foregroundColor(TrustCardColor.packTearStrip)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .overlay(Capsule().strokeBorder(TrustCardColor.packTrim, lineWidth: 1))
                    .padding(.top, 2)
            }

            Spacer()
            Spacer()
        }
        .frame(width: 212, height: 292)
        .background(
            ZStack {
                LinearGradient(colors: TrustCardColor.packGradient,
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                // 旋轉光芒層(rayRotate conic 金/靛微光 16s linear)
                if !reduceMotion {
                    CardBackRayLayer(tint: Color(hex: "8B8FE0"), duration: 16)
                }
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        // 內縮 7pt 金細線框 + 底部兩枚 22pt L 形金角飾
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(TrustCardColor.packTrim.opacity(0.6), lineWidth: 0.8)
                .padding(7)
        )
        .overlay(CornerOrnaments(color: TrustCardColor.packTrim, size: 22,
                                 inset: 12, bottomOnly: true))
        // 金箔雙層 inset 描邊(外 3.5 暗金 + 內 2 亮金)
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(TrustCardColor.packTrimDark, lineWidth: 3.5)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(TrustCardColor.packTrim, lineWidth: 2)
                .padding(1.5)
        )
        .holoShimmer(widthFraction: 0.46, duration: 4.2, opacity: 0.28)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: TrustCardColor.packGlow, radius: 23, x: 0, y: 22)
        .overlay(alignment: .top) {
            // KF1:3 條放射光線由撕條斜向射出
            if tearing && !reduceMotion {
                ZStack {
                    ForEach(0..<3, id: \.self) { index in
                        Capsule()
                            .fill(LinearGradient(colors: [.white.opacity(0.75), .clear],
                                                 startPoint: .bottom, endPoint: .top))
                            .frame(width: 3, height: 56)
                            .rotationEffect(.degrees([-24, 0, 24][index]))
                            .offset(x: CGFloat([-46, 0, 46][index]), y: -46)
                    }
                }
                .allowsHitTesting(false)
            }
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) {
                emblemPulsing = true
            }
        }
    }
}

// MARK: - 15a · 「今天為什麼值得看」卡

struct WhyTodayCard: View {
    let whyToday: WhyToday
    let onChip: (SourceChip) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("今天為什麼值得看")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(AppColor.inkTertiary)

            Text(whyToday.text)
                .font(.system(size: 14.5, weight: .bold, design: .rounded))
                .foregroundColor(AppColor.inkPrimary)
                .lineSpacing(8)
                .fixedSize(horizontal: false, vertical: true)

            // 出處 chips:nowrap,橫向捲動
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(whyToday.chips) { chip in
                        SourceChipView(chip: chip, onTap: onChip)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: Color(red: 120/255, green: 100/255, blue: 70/255).opacity(0.10),
                radius: 14, x: 0, y: 8)
    }
}
