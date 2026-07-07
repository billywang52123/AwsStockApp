import SwiftUI

// MARK: - 10a · 隱私儀表板 PrivacyDashboardView(spec 05)
// 一頁列出:我們有什麼(即時筆數)、沒有什麼、一鍵全部刪除(即時、可見)。

struct PrivacyDashboardView: View {
    @StateObject private var viewModel = PrivacyDashboardViewModel()
    @State private var showDeleteConfirm = false

    var body: some View {
        ZStack {
            AppColor.background.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    sloganCard

                    if let deleted = viewModel.deletedResult {
                        deletedCard(deleted).padding(.top, 16)
                    } else {
                        whatWeHaveCard.padding(.top, 16)
                    }

                    whatWeDontHaveCard.padding(.top, 12)

                    NavigationLink {
                        DataMapView()
                    } label: {
                        HStack {
                            Image(systemName: "map")
                                .font(.system(size: 15))
                                .foregroundColor(AppColor.primary)
                            Text("你的資料存在哪裡?")
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundColor(AppColor.inkPrimary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(AppColor.inkFaint)
                        }
                        .padding(.vertical, 14)
                        .padding(.horizontal, 18)
                        .background(Color.white)
                        .cornerRadius(16)
                        .shadow(color: Color(hex: "786446").opacity(0.06), radius: 9, x: 0, y: 6)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 12)

                    if viewModel.deletedResult == nil {
                        deleteButton.padding(.top, 16)

                        Text("伺服器上的資料當下即刪,不是排程刪除;本機顯示偏好也會一併清空。")
                            .font(.system(size: 11, design: .rounded))
                            .foregroundColor(AppColor.inkFaint)
                            .frame(maxWidth: .infinity)
                            .multilineTextAlignment(.center)
                            .padding(.top, 12)
                    }

                    if let error = viewModel.errorMessage {
                        Text(error)
                            .font(.system(size: 12, design: .rounded))
                            .foregroundColor(AppColor.roseStrong)
                            .padding(.top, 10)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
        .navigationTitle("隱私與安心")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            Task { await viewModel.load() }
        }
        .confirmationDialog("刪除你在這裡的所有資料?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("全部刪除", role: .destructive) {
                Task { await viewModel.deleteAll() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            if let s = viewModel.summary {
                Text("將刪除:持股紀錄 \(s.holdings) 筆、異動紀錄 \(s.activities) 筆、抽卡 \(s.cardResults) 筆、成就 \(s.achievements) 筆、提醒設定 \(s.reminderSettings) 筆。刪了就沒了,無法復原。")
            } else {
                Text("將刪除這個帳號名下的全部紀錄,無法復原。")
            }
        }
    }

    // MARK: - Slogan 卡

    private var sloganCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("我們的原則")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.7))
                .kerning(1)

            Text("我們連你的券商帳號都沒有")
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
                .lineSpacing(22 * 0.4)

            Text("不碰帳密、不能下單、不存身分。你給我們的只有三樣東西。")
                .font(.system(size: 12, design: .rounded))
                .foregroundColor(.white.opacity(0.7))
                .lineSpacing(12 * 0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 20)
        .padding(.horizontal, 22)
        .background(
            LinearGradient(
                colors: [AppColor.gradientCardTop, AppColor.gradientCardBottom],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        )
        .cornerRadius(22)
        .shadow(color: Color(hex: "5B5FA8").opacity(0.30), radius: 16, x: 0, y: 14)
        .padding(.top, 8)
    }

    // MARK: - 我們有什麼

    private var whatWeHaveCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("我們有什麼")
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundColor(AppColor.inkPrimary)
                Spacer()
                Text("即時筆數")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundColor(AppColor.inkQuaternary)
            }

            haveRow(icon: "briefcase", title: "持股紀錄", subtitle: "代號、股數、均價",
                    count: viewModel.summary.map { "\($0.holdings) 筆" })
            haveRow(icon: "clock.arrow.circlepath", title: "異動與抽卡紀錄", subtitle: "加買/賣出流水、每日卡",
                    count: viewModel.summary.map { "\($0.activities + $0.cardResults) 筆" })
            haveRow(icon: "bell", title: "提醒偏好", subtitle: "推播時段設定",
                    count: viewModel.summary.map { $0.reminderSettings > 0 ? "有" : "無" })

            Text("全部掛在一組匿名編號下,不連到你的姓名或 Email。")
                .font(.system(size: 11, design: .rounded))
                .foregroundColor(AppColor.inkQuaternary)
                .lineSpacing(11 * 0.6)
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 20)
        .background(Color.white)
        .cornerRadius(20)
        .shadow(color: Color(hex: "786446").opacity(0.06), radius: 9, x: 0, y: 6)
    }

    private func haveRow(icon: String, title: String, subtitle: String, count: String?) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(hex: "EEEEFA"))
                    .frame(width: 38, height: 38)
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(AppColor.primary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(AppColor.inkPrimary)
                Text(subtitle)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundColor(AppColor.inkTertiary)
            }
            Spacer()
            Text(count ?? "—")
                .font(.system(size: 15, weight: .heavy, design: .rounded).monospacedDigit())
                .foregroundColor(AppColor.inkPrimary)
        }
    }

    // MARK: - 我們沒有什麼

    private var whatWeDontHaveCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("我們沒有什麼")
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundColor(AppColor.inkPrimary)

            ForEach(["券商帳號密碼", "下單權限", "Email・姓名・身分證", "信用卡或銀行帳戶"], id: \.self) { item in
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(AppColor.bgTrack)
                            .frame(width: 38, height: 38)
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(AppColor.inkTertiary)
                    }
                    Text(item)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(AppColor.inkPrimary)
                    Spacer()
                    Text("沒有")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(AppColor.downText)
                        .padding(.vertical, 3)
                        .padding(.horizontal, 10)
                        .background(Color(hex: "EAF2EC"))
                        .clipShape(Capsule())
                }
            }
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 20)
        .background(Color.white)
        .cornerRadius(20)
        .shadow(color: Color(hex: "786446").opacity(0.06), radius: 9, x: 0, y: 6)
    }

    // MARK: - 刪除

    private var deleteButton: some View {
        Button {
            showDeleteConfirm = true
        } label: {
            Group {
                if viewModel.isDeleting {
                    ProgressView().tint(AppColor.upText)
                } else {
                    Text("一鍵全部刪除")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                }
            }
            .foregroundColor(AppColor.upText)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(AppColor.upText, lineWidth: 1.5)
            )
        }
        .disabled(viewModel.isDeleting)
    }

    /// 刪除完成:逐項顯示刪了幾筆,即時、可見
    private func deletedCard(_ deleted: PrivacySummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(AppColor.downText)
                Text("已全部刪除")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundColor(AppColor.inkPrimary)
            }

            ForEach([
                ("持股紀錄", deleted.holdings),
                ("異動紀錄", deleted.activities),
                ("抽卡紀錄", deleted.cardResults),
                ("成就紀錄", deleted.achievements),
                ("提醒設定", deleted.reminderSettings),
            ], id: \.0) { name, count in
                HStack(spacing: 8) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(AppColor.downText)
                    Text("\(name) \(count) 筆 · 已刪除")
                        .font(.system(size: 13, design: .rounded).monospacedDigit())
                        .foregroundColor(AppColor.inkSecondary)
                }
            }

            Text("這個匿名編號名下已經沒有任何資料;本機顯示偏好也清空了。")
                .font(.system(size: 11, design: .rounded))
                .foregroundColor(AppColor.inkQuaternary)
                .lineSpacing(11 * 0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 18)
        .padding(.horizontal, 20)
        .background(Color.white)
        .cornerRadius(20)
        .shadow(color: Color(hex: "786446").opacity(0.06), radius: 9, x: 0, y: 6)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}
