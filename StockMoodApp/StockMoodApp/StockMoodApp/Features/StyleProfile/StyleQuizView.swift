import SwiftUI

/// 16a 投資風格問卷:單選、無標準答案、可整份跳過;交卷後 push 16b 結果頁。
struct StyleQuizView: View {
    @StateObject private var viewModel = StyleQuizViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var showResult = false
    /// 交卷完成後由結果頁「開始使用」關閉整個測驗流程
    var onFinished: (() -> Void)? = nil

    var body: some View {
        ZStack {
            AppColor.background.ignoresSafeArea()

            if viewModel.isLoading {
                ProgressView("正在準備題目...")
            } else if viewModel.hasError && viewModel.questionnaire == nil {
                ErrorStateView(message: viewModel.errorMessage) {
                    Task { await viewModel.load() }
                }
            } else if let question = viewModel.currentQuestion {
                VStack(alignment: .leading, spacing: 0) {
                    // 進度條
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(AppColor.bgTrack)
                            Capsule()
                                .fill(
                                    LinearGradient(colors: [AppColor.primary, Color(hex: "9A9EE8")],
                                                   startPoint: .leading, endPoint: .trailing)
                                )
                                .frame(width: geo.size.width * viewModel.progress)
                                .animation(.spring(response: 0.4, dampingFraction: 0.85), value: viewModel.progress)
                        }
                    }
                    .frame(height: 6)
                    .padding(.top, 14)

                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 0) {
                            // 題目
                            Text(question.title)
                                .font(.system(size: 23, weight: .heavy, design: .serif))
                                .foregroundColor(AppColor.inkPrimary)
                                .lineSpacing(8)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, 30)
                            Text(question.subtitle.isEmpty ? "沒有標準答案，選最像平常的你就好" : question.subtitle)
                                .font(.system(size: 12.5, design: .rounded))
                                .foregroundColor(AppColor.inkQuaternary)
                                .lineSpacing(5)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, 6)

                            // 選項卡
                            VStack(spacing: 12) {
                                ForEach(question.options) { option in
                                    QuizOptionCard(
                                        option: option,
                                        isSelected: viewModel.currentAnswer == option.code
                                    ) {
                                        viewModel.select(option: option.code)
                                    }
                                }
                            }
                            .padding(.top, 22)
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom, 20)
                    }
                    .id(viewModel.currentIndex)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .offset(y: 8)),
                        removal: .opacity
                    ))

                    bottomBar
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("投資風格測驗")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundColor(AppColor.inkPrimary)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Text("\(viewModel.currentIndex + 1)/\(max(viewModel.questions.count, 1))")
                    .font(.system(size: 13, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(AppColor.inkQuaternary)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    // 題內返回上一題;第一題時返回上一頁
                    if !viewModel.goBack() { dismiss() }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(AppColor.primary)
                        .frame(width: 44, height: 44, alignment: .leading)
                }
            }
        }
        .task { await viewModel.load() }
        .navigationDestination(isPresented: $showResult) {
            StyleResultView(
                mode: .afterQuiz,
                preloadedProfile: viewModel.submittedProfile,
                // 「開始使用」:未指定收尾行為時,連同問卷一起退出整個測驗流程
                onFinished: onFinished ?? { dismiss() }
            )
        }
    }

    // MARK: - 底部 CTA + 跳過 + 免責帶

    private var bottomBar: some View {
        VStack(spacing: 10) {
            Button {
                if viewModel.isLastQuestion {
                    Task {
                        if await viewModel.submit() { showResult = true }
                    }
                } else {
                    HapticManager.shared.triggerSelection()
                    viewModel.goNext()
                }
            } label: {
                Group {
                    if viewModel.isSubmitting {
                        ProgressView().tint(.white)
                    } else {
                        Text(viewModel.isLastQuestion ? "看結果" : "下一題")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(AppColor.primary)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: AppColor.primary.opacity(0.35), radius: 12, x: 0, y: 8)
            }
            .buttonStyle(PressScaleButtonStyle())
            .disabled(viewModel.currentAnswer == nil || viewModel.isSubmitting)
            .opacity(viewModel.currentAnswer == nil ? 0.4 : 1)

            Button {
                dismiss()
            } label: {
                Text("之後再測，先逛逛")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundColor(AppColor.inkQuaternary)
                    .frame(minHeight: 44)
            }

            Text("測驗結果只用來調整說明的口吻與重點，不構成投資建議")
                .font(.system(size: 9.5, design: .rounded))
                .foregroundColor(AppColor.inkFaint)
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .background(AppColor.background)
    }
}

// MARK: - 16a 選項卡

struct QuizOptionCard: View {
    let option: QuestionnaireOption
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                // 左側圓:未選空心、選中實心 + 白勾
                ZStack {
                    Circle()
                        .strokeBorder(isSelected ? Color.clear : Color(hex: "DDD8CC"), lineWidth: 2)
                        .background(Circle().fill(isSelected ? AppColor.primary : Color.clear))
                        .frame(width: 26, height: 26)
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                            .transition(.scale(scale: 0.6).combined(with: .opacity))
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(option.label)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(AppColor.inkPrimary)
                    Text(option.description)
                        .font(.system(size: 12, design: .rounded))
                        .foregroundColor(AppColor.inkTertiary)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 16)
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? AppColor.primaryBgTint : AppColor.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(isSelected ? AppColor.primary : Color(hex: "E9E5DA"), lineWidth: 2)
            )
            .shadow(color: isSelected ? AppColor.primary.opacity(0.18) : .clear, radius: 12, x: 0, y: 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: isSelected)
    }
}
