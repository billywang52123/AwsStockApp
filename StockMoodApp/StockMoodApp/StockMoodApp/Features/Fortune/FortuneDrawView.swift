import SwiftUI

// MARK: - 每日御神籤主頁(12a 入口 / 12b 搖籤 / 13 開籤光效 / 12c 籤詩)
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
                case .result:
                    if let fortune = viewModel.fortune {
                        FortuneResultView(fortune: fortune)
                            .transition(.opacity)
                    }
                }

                // 13a/13b 開籤瞬間光效(金光 / 黑煙,約 1.8s 後收斂)
                if viewModel.phase == .revealing, let fortune = viewModel.fortune {
                    FortuneRevealEffect(level: fortune.overallLevel)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.35), value: viewModel.phase == .result)
            .navigationTitle("今日運勢籤")
            .navigationBarTitleDisplayMode(.inline)
            .task { await viewModel.loadToday() }
        }
    }
}

// MARK: - 日期字串(「7 月 9 日 · 週四」)
private func fortuneDateText() -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "zh_TW")
    formatter.dateFormat = "M 月 d 日"
    let week = ["日", "一", "二", "三", "四", "五", "六"][Calendar.current.component(.weekday, from: Date()) - 1]
    return "\(formatter.string(from: Date())) · 週\(week)"
}

// MARK: - 12a · 搖籤入口(籤筒待機微晃 rock ±2.5° 3.2s)
struct FortuneEntryView: View {
    @ObservedObject var viewModel: FortuneViewModel
    @State private var rocking = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            Text(fortuneDateText())
                .font(.system(size: 13, design: .rounded))
                .foregroundColor(AppColor.inkTertiary)
                .padding(.top, 12)

            Spacer()

            FortuneTubeView()
                .rotationEffect(.degrees(rocking && !reduceMotion ? 2.5 : -2.5))
                .animation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true), value: rocking)
                .onAppear { rocking = true }

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
                .padding(.top, 12)

            Spacer()
        }
        .padding(.horizontal, 28)
    }
}

// MARK: - 12b · 搖籤動畫(筒身傾斜 26° 高頻搖動 ±13° 0.55s,籤支彈出)
struct FortuneShakeView: View {
    let isRevealing: Bool
    let fortune: FortuneResult?
    @State private var shaking = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            Text(fortuneDateText())
                .font(.system(size: 13, design: .rounded))
                .foregroundColor(AppColor.inkTertiary)
                .padding(.top, 12)

            Spacer()

            ZStack(alignment: .top) {
                FortuneTubeView()
                    .rotationEffect(.degrees(isRevealing || reduceMotion ? 0 : 26))
                    .rotationEffect(.degrees(shaking && !isRevealing && !reduceMotion ? 13 : -13))
                    .animation(
                        isRevealing ? .spring(response: 0.5, dampingFraction: 0.8)
                                    : .easeInOut(duration: 0.275).repeatForever(autoreverses: true),
                        value: shaking
                    )
                    .animation(.spring(response: 0.5, dampingFraction: 0.8), value: isRevealing)

                // 籤支從筒口彈出(stickPop)
                if isRevealing, let fortune {
                    FortuneStickView(numberText: String(fortune.stickLabel.dropFirst().dropLast()))
                        .offset(y: -86)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .zIndex(1)
                }
            }
            .animation(.spring(response: 0.55, dampingFraction: 0.65), value: isRevealing)

            Text(isRevealing ? "籤來了!" : "搖籤中…")
                .font(.system(size: 19, weight: .bold, design: .serif))
                .kerning(4)
                .foregroundColor(Color(hex: "4A4770"))
                .padding(.top, 40)

            Text(isRevealing ? "正在為你展開籤詩" : "正在依你的持股與今日市場求籤")
                .font(.system(size: 13, design: .rounded))
                .foregroundColor(AppColor.inkTertiary)
                .padding(.top, 6)

            Spacer()
        }
        .padding(.horizontal, 28)
        .onAppear {
            shaking = true
            // 搖籤節奏 haptic
            for delay in stride(from: 0.0, to: 2.2, by: 0.55) {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    HapticManager.shared.triggerImpact(style: .medium)
                }
            }
        }
    }
}

// MARK: - 籤筒(SwiftUI 繪製:木紋色筒身 + 一束籤支)
struct FortuneTubeView: View {
    var body: some View {
        ZStack(alignment: .top) {
            // 筒內籤支
            HStack(spacing: 5) {
                ForEach(0..<7, id: \.self) { index in
                    Capsule()
                        .fill(Color(hex: index % 2 == 0 ? "E8D8B8" : "DECDA8"))
                        .frame(width: 9, height: [46, 60, 52, 66, 50, 58, 44][index])
                        .offset(y: CGFloat([8, -4, 2, -8, 4, -2, 10][index]))
                }
            }
            .offset(y: -26)

            // 筒身
            VStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(hex: "8A6A4A"))
                    .frame(width: 128, height: 14)
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "A8845E"), Color(hex: "8A6A4A")],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                    .frame(width: 118, height: 150)
                    .overlay(
                        // 「安心籤」直式標籤
                        VStack(spacing: 4) {
                            ForEach(Array("安心籤".map(String.init).enumerated()), id: \.offset) { _, char in
                                Text(char)
                                    .font(.system(size: 15, weight: .bold, design: .serif))
                                    .foregroundColor(Color(hex: "6A4E32"))
                            }
                        }
                        .padding(.vertical, 10)
                        .padding(.horizontal, 8)
                        .background(Color(hex: "F7F0E2"))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    )
            }
            .padding(.top, 30)
        }
        .frame(height: 210)
        .shadow(color: Color(hex: "786446").opacity(0.25), radius: 14, x: 0, y: 10)
    }
}

// MARK: - 彈出的籤支(木片 + 中文數字)
struct FortuneStickView: View {
    let numberText: String

    var body: some View {
        VStack(spacing: 3) {
            Circle()
                .fill(Color(hex: "C97F7F"))
                .frame(width: 7, height: 7)
            ForEach(Array(numberText.map(String.init).enumerated()), id: \.offset) { _, char in
                Text(char)
                    .font(.system(size: 16, weight: .heavy, design: .serif))
                    .foregroundColor(Color(hex: "6A4E32"))
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 9)
        .background(Color(hex: "F2E6C8"))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(Color(hex: "D9C49A"), lineWidth: 1)
        )
        .shadow(color: Color(hex: "786446").opacity(0.3), radius: 8, x: 0, y: 5)
    }
}
