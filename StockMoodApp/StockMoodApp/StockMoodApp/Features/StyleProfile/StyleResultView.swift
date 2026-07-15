import SwiftUI

/// 16b 投資風格結果:交卷後結果頁,也是設定頁「我的投資風格」再訪入口。
struct StyleResultView: View {
    enum Mode {
        case afterQuiz   // 交卷後:CTA「開始使用」
        case revisit     // 設定頁再訪:CTA 換「重新測驗」描邊樣式
    }

    var mode: Mode = .revisit
    /// 交卷後直接帶入結果,避免再打一次 API
    var preloadedProfile: InvestmentProfileRead? = nil
    var onFinished: (() -> Void)? = nil

    @StateObject private var viewModel = InvestmentProfileViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var axisAnimated = false
    @State private var showQuiz = false

    private var profile: InvestmentProfileRead? { viewModel.profile ?? preloadedProfile }

    var body: some View {
        ZStack {
            AppColor.background.ignoresSafeArea()

            if viewModel.isLoading && profile == nil {
                ProgressView("正在整理你的風格...")
            } else if let profile {
                if profile.questionnaireCompleted {
                    resultBody(profile)
                } else {
                    notTestedBody
                }
            } else if viewModel.hasError {
                ErrorStateView(message: viewModel.errorMessage) {
                    Task { await viewModel.load() }
                }
            }
        }
        .navigationTitle("我的投資風格")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if preloadedProfile == nil { await viewModel.load() }
            else { viewModel.promptContext = try? await DependencyContainer.shared.investmentProfileService.getPromptContext() }
        }
        .navigationDestination(isPresented: $showQuiz) {
            StyleQuizView(onFinished: onFinished)
        }
        .onChange(of: showQuiz) { _, isPresented in
            // 從測驗流程返回後重載(.task 只跑一次),讓再訪頁反映最新結果
            if !isPresented { Task { await viewModel.load() } }
        }
    }

    // MARK: - 尚未測驗

    private var notTestedBody: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 44))
                .foregroundColor(AppColor.inkQuaternary)
            Text("還沒做過風格測驗")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundColor(AppColor.inkPrimary)
            Text("5 分鐘內完成，AI 之後會用更貼近你的方式說明")
                .font(.system(size: 13, design: .rounded))
                .foregroundColor(AppColor.inkTertiary)
            Button {
                showQuiz = true
            } label: {
                Text("開始測驗")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 40)
                    .frame(height: 50)
                    .background(AppColor.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .padding(.top, 8)
        }
        .padding(24)
    }

    // MARK: - 結果內容

    private func resultBody(_ profile: InvestmentProfileRead) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                if mode == .afterQuiz {
                    Text("測驗完成")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundColor(AppColor.inkTertiary)
                        .padding(.top, 8)
                }
                Text("你的投資風格")
                    .font(.system(size: 26, weight: .heavy, design: .serif))
                    .foregroundColor(AppColor.inkPrimary)
                    .padding(.top, 6)

                StyleHeroCard(style: profile.preferenceStyle)
                    .padding(.top, 18)
                    .entrance(index: 0, stagger: 0.1)

                StyleAxisCard(dimensions: profile.styleDimensions, animated: $axisAnimated)
                    .padding(.top, 16)
                    .entrance(index: 1, stagger: 0.1)

                if let context = viewModel.promptContext {
                    TonerPreviewCard(principles: context.appliedPrinciples)
                        .padding(.top, 12)
                        .entrance(index: 2, stagger: 0.1)
                }

                // CTA
                Button {
                    if mode == .afterQuiz {
                        if let onFinished { onFinished() } else { dismiss() }
                    } else {
                        showQuiz = true
                    }
                } label: {
                    Text(mode == .afterQuiz ? "開始使用" : "重新測驗")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundColor(mode == .afterQuiz ? .white : AppColor.primary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(mode == .afterQuiz ? AppColor.primary : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(AppColor.primary, lineWidth: mode == .afterQuiz ? 0 : 2)
                        )
                        .shadow(color: mode == .afterQuiz ? AppColor.primary.opacity(0.35) : .clear,
                                radius: 12, x: 0, y: 8)
                }
                .buttonStyle(PressScaleButtonStyle())
                .padding(.top, 24)

                Text(mode == .afterQuiz ? "重新測驗 · 隨時可在設定裡改" : "重測後,AI 的說明口吻會跟著更新")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundColor(AppColor.inkQuaternary)
                    .frame(minHeight: 44)

                DisclaimerBlock(text: "風格分類僅用於調整說明方式，不構成投資建議")
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
    }
}

// MARK: - 16b 風格大卡(該型主色 150° 漸層 + 光暈)

struct StyleHeroCard: View {
    let style: StyleRead
    @State private var breathe = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // 裝飾光暈圓(緩慢 breathe)
            Circle()
                .fill(Color.white.opacity(0.14))
                .frame(width: 150, height: 150)
                .blur(radius: 24)
                .offset(x: 40, y: -46)
                .opacity(breathe ? 0.95 : 0.5)
                .animation(.easeInOut(duration: 3).repeatForever(autoreverses: true), value: breathe)

            VStack(spacing: 10) {
                Text("你的分型")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(Color(hex: "F0EEFF"))
                    .padding(.vertical, 4)
                    .padding(.horizontal, 12)
                    .background(Color.white.opacity(0.16))
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.35), lineWidth: 1))
                    .clipShape(Capsule())

                Text(style.label)
                    .font(.system(size: 34, weight: .heavy, design: .serif))
                    .kerning(4)
                    .foregroundColor(.white)
                    .shadow(color: Color(hex: "1E1E50").opacity(0.35), radius: 7, x: 0, y: 2)

                Text(style.summary)
                    .font(.system(size: 13, design: .rounded))
                    .foregroundColor(.white.opacity(0.88))
                    .multilineTextAlignment(.center)
                    .lineSpacing(6)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .padding(.horizontal, 22)
        }
        .background(
            LinearGradient(colors: InvestStyleTheme.gradient(for: style.code),
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: InvestStyleTheme.gradient(for: style.code).last?.opacity(0.35) ?? .clear,
                radius: 16, x: 0, y: 14)
        .onAppear { breathe = true }
    }
}

// MARK: - 16b 四維度光譜卡

struct StyleAxisCard: View {
    let dimensions: StyleDimensions
    @Binding var animated: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text("你的四個維度")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .kerning(2)
                .foregroundColor(AppColor.inkTertiary)

            ForEach(Array(InvestStyleTheme.axes.enumerated()), id: \.element.key) { index, axis in
                let score = InvestStyleTheme.value(of: dimensions, key: axis.key)
                VStack(spacing: 6) {
                    HStack {
                        Text(axis.name)
                            .font(.system(size: 12.5, weight: .bold, design: .rounded))
                            .foregroundColor(AppColor.inkPrimary)
                        Spacer()
                        Text(InvestStyleTheme.valueLabel(key: axis.key, score: score))
                            .font(.system(size: 12.5, weight: .bold, design: .rounded))
                            .foregroundColor(AppColor.primary)
                            .opacity(animated ? 1 : 0)
                    }

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color(hex: "EFEDEA"))
                            Capsule()
                                .fill(LinearGradient(colors: [Color(hex: "9A9EE8"), AppColor.primary],
                                                     startPoint: .leading, endPoint: .trailing))
                                .frame(width: animated ? geo.size.width * CGFloat(score) / 100 : 0)
                        }
                    }
                    .frame(height: 7)
                    .animation(
                        .spring(response: 0.6, dampingFraction: 0.85).delay(Double(index) * 0.08),
                        value: animated
                    )
                }
            }
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColor.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Color(hex: "786446").opacity(0.06), radius: 9, x: 0, y: 6)
        .onAppear {
            // 首次進場 width 0 → 值,stagger 80ms/列
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { animated = true }
        }
    }
}

// MARK: - 16b AI 口吻預覽卡

struct TonerPreviewCard: View {
    let principles: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("AI 之後會這樣跟你說話")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(Color(hex: "5A5794"))

            ForEach(principles, id: \.self) { principle in
                HStack(alignment: .top, spacing: 7) {
                    Text("“")
                        .font(.system(size: 15, weight: .heavy, design: .serif))
                        .foregroundColor(AppColor.primary.opacity(0.6))
                    Text(principle)
                        .font(.system(size: 13, design: .rounded))
                        .foregroundColor(Color(hex: "4A4770"))
                        .lineSpacing(6)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColor.primaryBgTint)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
