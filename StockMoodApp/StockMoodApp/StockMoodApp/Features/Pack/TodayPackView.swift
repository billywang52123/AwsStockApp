import SwiftUI

// MARK: - 每日抽卡包主頁(spec 06 · 15a 入口 → 15b–15e 開包 → 15f/g/h 瀏覽)
// 取代御神籤:AI 每天把整體庫存整理成一包三張卡(事實 → 推論 → 陪伴,順序不可亂)

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
                case .opening, .hand, .browsing:
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
        case .hand: return 20
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

struct PackCoverCard: View {
    let pack: DailyPack
    /// KF1 撕開態:虛線區光帶橫掃 + 放射光線
    let tearing: Bool

    @State private var sweeping = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            // 頂部「— 由此撕開 —」虛線分隔區(44 高)
            ZStack {
                LinearGradient(colors: [.white.opacity(0.10), .clear],
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
                    .foregroundColor(.white.opacity(0.75))
                    Spacer()
                    DashedLine()
                        .stroke(Color.white.opacity(0.6),
                                style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                        .frame(height: 1.5)
                }
                .padding(.top, 6)

                // KF1:一條全息光帶沿虛線橫掃(glowPulse)
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
                    .kerning(1.5)
                    .foregroundColor(.white.opacity(0.8))
                Text("我的庫存")
                    .font(.system(size: 32, weight: .heavy, design: .serif))
                    .foregroundColor(.white)
                Text("\(pack.holdingsCount) 檔 · \(pack.totalValueText)")
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.9))
            }

            Spacer()
            Spacer()
        }
        .frame(width: 212, height: 292)
        .background(
            LinearGradient(colors: TrustCardColor.packGradient,
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .holoShimmer(widthFraction: 0.46, duration: 4.2, opacity: 0.28)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: TrustCardColor.packGlow, radius: 23, x: 0, y: 22)
        .overlay(alignment: .top) {
            // KF1:3 條放射光線由虛線區斜向射出
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
