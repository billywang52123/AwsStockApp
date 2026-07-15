import SwiftUI

/// 18c 設定「個人化」分組:投資風格 / 投資習慣兩列,隨時可補測、重測;
/// 另保留 16e 風格轉變列(含未讀紅點)。
/// 未測驗時風格列右側掛金色 chip「去測驗 · 2 分鐘」(靜態不閃爍,安撫原則)直進 16a;
/// 已測驗改顯示型名進 16b(再訪模式,CTA = 重新測驗)。
struct SettingsPersonalizationSection: View {
    @ObservedObject private var styleShiftCenter = StyleShiftCenter.shared
    @State private var profile: InvestmentProfileRead?
    @State private var showQuiz = false

    private var quizCompleted: Bool { profile?.questionnaireCompleted == true }

    var body: some View {
        Section {
            styleRow
            habitRow
            shiftRow
        } header: {
            Text("個人化").font(.system(.footnote, design: .rounded))
        } footer: {
            VStack(alignment: .leading, spacing: 10) {
                // 分組下說明盒:未測也不催促(中性口吻先行)
                Text("還沒測驗也沒關係 —— AI 會先用中性口吻說明。測完之後，說明的語氣和重點會照你的風格調整。")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundColor(Color(hex: "5A5794"))
                    .lineSpacing(5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 13)
                    .padding(.horizontal, 16)
                    .background(AppColor.primaryBgTint)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                Text("風格測驗結果只用來調整說明口吻，不構成投資建議")
                    .font(.system(.caption2, design: .rounded))
            }
            .padding(.top, 6)
        }
    }

    // MARK: - 投資風格列

    @ViewBuilder
    private var styleRow: some View {
        Group {
            if quizCompleted {
                // 已測驗:右側型名 › 進 16b(再訪模式)
                NavigationLink(destination: StyleResultView(mode: .revisit)) {
                    rowContent(
                        icon: "person.text.rectangle.fill",
                        iconBg: AppColor.primaryBgTint,
                        iconColor: AppColor.primary,
                        title: "投資風格",
                        subtitle: profile?.preferenceStyle.summary ?? ""
                    ) {
                        Text(profile?.preferenceStyle.label ?? "")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundColor(AppColor.primary)
                    }
                }
            } else {
                // 未測驗:金色提示 chip 進 16a(整列可點,light haptic)
                Button {
                    HapticManager.shared.triggerImpact(style: .light)
                    showQuiz = true
                } label: {
                    rowContent(
                        icon: "person.text.rectangle.fill",
                        iconBg: AppColor.primaryBgTint,
                        iconColor: AppColor.primary,
                        title: "投資風格",
                        subtitle: "尚未測驗"
                    ) {
                        Text("去測驗 · 2 分鐘")
                            .font(.system(size: 12.5, weight: .bold, design: .rounded))
                            .foregroundColor(AppColor.amberStrong)
                            .padding(.vertical, 6)
                            .padding(.horizontal, 13)
                            .background(AppColor.amberBg)
                            .overlay(Capsule().strokeBorder(AppColor.amberBorder, lineWidth: 1.5))
                            .clipShape(Capsule())
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .navigationDestination(isPresented: $showQuiz) {
            StyleQuizView()
        }
        .task { await reload() }
        .onAppear {
            // push 返回(測驗 / 重新測驗完成)後重載,讓副標與 chip 反映最新狀態
            Task { await reload() }
        }
    }

    // MARK: - 投資習慣列(16d,自動推算免填寫)

    private var habitRow: some View {
        NavigationLink(destination: InvestHabitView()) {
            rowContent(
                icon: "chart.bar.fill",
                iconBg: AppColor.downBgTint,
                iconColor: AppColor.downStrong,
                title: "投資習慣",
                subtitle: "從持股自動整理 · 免填寫"
            ) {
                Text("已啟用")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(AppColor.inkTertiary)
            }
        }
    }

    // MARK: - 風格轉變列(16e,未讀紅點)

    private var shiftRow: some View {
        NavigationLink(destination: StyleShiftView()) {
            rowContent(
                icon: "arrow.triangle.2.circlepath",
                iconBg: AppColor.bgTrack,
                iconColor: AppColor.inkSecondary,
                title: "風格轉變",
                subtitle: "持股更新後的風格重算紀錄"
            ) {
                if styleShiftCenter.hasUnseenShift {
                    Circle()
                        .fill(AppColor.danger)
                        .frame(width: 8, height: 8)
                }
            }
        }
    }

    // MARK: - 共用列版型(40 R13 icon 磚 + 主副標 + 右側狀態)

    private func rowContent(
        icon: String,
        iconBg: Color,
        iconColor: Color,
        title: String,
        subtitle: String,
        @ViewBuilder trailing: () -> some View
    ) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(iconBg)
                    .frame(width: 40, height: 40)
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(iconColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(AppColor.inkPrimary)
                Text(subtitle)
                    .font(.system(size: 12, design: .rounded))
                    .foregroundColor(AppColor.inkTertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            trailing()
        }
        .padding(.vertical, 4)
        .frame(minHeight: 44)
    }

    private func reload() async {
        profile = try? await DependencyContainer.shared.investmentProfileService.getProfile()
    }
}
