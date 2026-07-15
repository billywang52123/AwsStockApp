import SwiftUI

/// 18b 跳過測驗後的首頁提醒:未做測驗(`styleProfile` 未落)且未在 7 天冷卻期內時,
/// 今日首頁在焦慮分數環卡下方插入一張可關閉、不擋內容的補測提醒卡。
/// 顯示邏輯自含:後端 `questionnaireCompleted` 為單一真實來源,
/// 關閉時間存 `AppPreferenceStore.styleNudgeDismissedAt`。
struct HomeStyleNudgeSection: View {
    @State private var needsQuiz = false        // 後端回報尚未完成測驗
    @State private var entranceDone = false     // 進場動畫完成(延遲 0.4s,晚於分數環)
    @State private var dismissedByUser = false  // 本次關閉(同時寫入 7 天冷卻)
    @State private var showQuiz = false

    var body: some View {
        Group {
            if needsQuiz && !dismissedByUser {
                HomeStyleNudgeCard(
                    onStartQuiz: {
                        HapticManager.shared.triggerImpact(style: .light)
                        showQuiz = true
                    },
                    onDismiss: dismissCard
                )
                .opacity(entranceDone ? 1 : 0)
                .offset(y: entranceDone ? 0 : 10)
                .transition(.opacity) // 關閉時 fade,外層 VStack 動畫補上高度 collapse
            }
        }
        .navigationDestination(isPresented: $showQuiz) {
            StyleQuizView()
        }
        .task { await reload() }
        .onChange(of: showQuiz) { _, isPresented in
            // 從測驗流程返回後重查:測完即收起提醒
            if !isPresented { Task { await reload() } }
        }
    }

    private func reload() async {
        guard AppPreferenceStore.shared.shouldShowStyleNudge, !dismissedByUser else { return }
        guard let profile = try? await DependencyContainer.shared.investmentProfileService.getProfile() else {
            return // 查不到就不打擾(提醒卡缺席不影響任何功能)
        }
        if profile.questionnaireCompleted {
            withAnimation(.easeInOut(duration: 0.3)) { needsQuiz = false }
        } else if !needsQuiz {
            needsQuiz = true
            // 首頁載入後延遲 0.4s fade + 上移 10pt spring 0.5s(晚於分數環,不搶焦點)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { entranceDone = true }
            }
        }
    }

    private func dismissCard() {
        AppPreferenceStore.shared.styleNudgeDismissedAt = Date()
        withAnimation(.easeInOut(duration: 0.3)) { dismissedByUser = true }
    }
}

/// 18b 提醒卡本體(純顯示)
struct HomeStyleNudgeCard: View {
    let onStartQuiz: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                // 左 44 R15 時鐘 icon
                ZStack {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(AppColor.primaryBgTint)
                        .frame(width: 44, height: 44)
                    Image(systemName: "clock.fill")
                        .font(.system(size: 19))
                        .foregroundColor(AppColor.primary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("花 2 分鐘，讓 AI 更懂你")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(AppColor.inkPrimary)
                    Text("你還沒做風格測驗 —— 做完後，說明會照你的風格調整口吻。")
                        .font(.system(size: 12.5, design: .rounded))
                        .foregroundColor(AppColor.inkTertiary)
                        .lineSpacing(5)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                // 右上 30 關閉圓(命中區 ≥ 44)
                Button(action: onDismiss) {
                    ZStack {
                        Circle()
                            .fill(Color(hex: "F4F1EA"))
                            .frame(width: 30, height: 30)
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(AppColor.inkTertiary)
                    }
                    .frame(width: 44, height: 44, alignment: .topTrailing)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.top, -8)
                .padding(.trailing, -8)
            }

            HStack(spacing: 10) {
                Button(action: onStartQuiz) {
                    Text("去測驗")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(AppColor.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(PressScaleButtonStyle())

                Button(action: onDismiss) {
                    Text("下次再說")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(AppColor.inkTertiary)
                        .frame(width: 96, height: 44)
                        .background(Color(hex: "F4F1EA"))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            Text("未測驗時，AI 先用中性口吻說明，功能不受影響")
                .font(.system(size: 11, design: .rounded))
                .foregroundColor(AppColor.inkFaint)
        }
        .padding(18)
        .background(AppColor.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color(hex: "DDDAF0"), lineWidth: 1.5)
        )
        .shadow(color: AppColor.primary.opacity(0.12), radius: 12, x: 0, y: 10)
    }
}
