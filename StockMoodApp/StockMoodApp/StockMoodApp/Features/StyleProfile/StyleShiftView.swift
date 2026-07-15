import SwiftUI

/// 16e 風格轉變:持股更新後重算,顯示「原風格 → 新風格」+ 指標變化 + 快照時間軸。
struct StyleShiftView: View {
    @StateObject private var viewModel = InvestmentProfileViewModel()

    var body: some View {
        ZStack {
            AppColor.background.ignoresSafeArea()

            if viewModel.isLoading && viewModel.profile == nil {
                ProgressView("正在對照你的風格變化...")
            } else if viewModel.hasError && viewModel.profile == nil {
                ErrorStateView(message: viewModel.errorMessage) {
                    Task { await viewModel.load() }
                }
            } else if viewModel.profile != nil {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("風格轉變")
                            .font(.system(size: 26, weight: .heavy, design: .serif))
                            .foregroundColor(AppColor.inkPrimary)
                        Text("你更新了持股，AI 重新看了你的習慣")
                            .font(.system(size: 12.5, design: .rounded))
                            .foregroundColor(AppColor.inkTertiary)
                            .padding(.top, 4)

                        if let current = viewModel.latestShift.current {
                            // 異動摘要列
                            changeSummaryRow(current)
                                .padding(.top, 16)
                                .entrance(index: 0, stagger: 0.1)

                            // 轉變對照卡
                            ShiftCompareCard(
                                previous: viewModel.latestShift.previous,
                                current: current
                            )
                            .padding(.top, 14)
                            .entrance(index: 1, stagger: 0.1)

                            // 時間軸卡
                            StyleTimelineCard(snapshots: Array(viewModel.history.prefix(6)))
                                .padding(.top, 14)
                                .entrance(index: 2, stagger: 0.1)

                            // AI 調整提醒卡
                            shiftAdviceCard(current)
                                .padding(.top, 12)
                                .entrance(index: 3, stagger: 0.1)
                        } else {
                            emptyState
                                .padding(.top, 40)
                        }

                        // 手動重算
                        Button {
                            Task { await viewModel.refreshSnapshot() }
                        } label: {
                            HStack(spacing: 8) {
                                if viewModel.isRefreshing {
                                    ProgressView().tint(AppColor.primary)
                                } else {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.system(size: 13, weight: .semibold))
                                }
                                Text("用目前持股重新對照一次")
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                            }
                            .foregroundColor(AppColor.primary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(AppColor.primary, lineWidth: 1.5)
                            )
                        }
                        .disabled(viewModel.isRefreshing)
                        .padding(.top, 20)

                        DisclaimerBlock(text: "風格分類僅描述現況，不評價你的選擇，也不構成投資建議")
                            .padding(.top, 16)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 40)
                }
                .refreshable { await viewModel.load() }
            }
        }
        .navigationTitle("風格轉變")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.load()
            // 看過即熄滅紅點,並記住已讀到哪筆快照
            StyleShiftCenter.shared.markSeen(latestSnapshotId: viewModel.history.first?.id)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 36))
                .foregroundColor(AppColor.inkQuaternary)
            Text("還沒有習慣快照\n更新持股或完成風格測驗後，這裡會開始記錄你的變化")
                .font(.system(size: 13, design: .rounded))
                .foregroundColor(AppColor.inkTertiary)
                .multilineTextAlignment(.center)
                .lineSpacing(5)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 異動摘要列

    private func changeSummaryRow(_ snapshot: HabitSnapshotRead) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(snapshot.createdAt.formatted(.dateTime.month().day()))
                .font(.system(size: 11, design: .rounded))
                .monospacedDigit()
                .foregroundColor(Color(hex: "5A5794"))
            Text(snapshot.changeSummary)
                .font(.system(size: 12.5, design: .rounded))
                .foregroundColor(Color(hex: "4A4770"))
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 11)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColor.primaryBgTint)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - AI 調整提醒卡

    private func shiftAdviceCard(_ snapshot: HabitSnapshotRead) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("AI 之後會多留意一件事")
                .font(.system(size: 12.5, weight: .bold, design: .rounded))
                .foregroundColor(AppColor.amberStrong)
            Text(snapshot.investmentHabit.summary)
                .font(.system(size: 12, design: .rounded))
                .foregroundColor(AppColor.amberText)
                .lineSpacing(6)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 13)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColor.amberBg)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(AppColor.amberBorder, lineWidth: 1.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// MARK: - 16e 轉變對照卡

struct ShiftCompareCard: View {
    let previous: HabitSnapshotRead?
    let current: HabitSnapshotRead
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 14) {
            // 原本 → 現在
            HStack(spacing: 12) {
                VStack(spacing: 5) {
                    Text(previous?.observedStyle.label ?? "首次紀錄")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(AppColor.inkTertiary)
                        .padding(.vertical, 7)
                        .padding(.horizontal, 14)
                        .background(Color(hex: "EFEDEA"))
                        .clipShape(Capsule())
                    Text("原本")
                        .font(.system(size: 10.5, design: .rounded))
                        .foregroundColor(AppColor.inkFaint)
                }

                Image(systemName: "arrow.right")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(AppColor.primary)
                    .opacity(appeared ? 1 : 0)

                VStack(spacing: 5) {
                    Text(current.observedStyle.label)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.vertical, 7)
                        .padding(.horizontal, 14)
                        .background(
                            LinearGradient(
                                colors: InvestStyleTheme.gradient(for: current.observedStyle.code),
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            )
                        )
                        .clipShape(Capsule())
                        .shadow(color: InvestStyleTheme.color(for: current.observedStyle.code).opacity(0.35),
                                radius: 8, x: 0, y: 5)
                        .scaleEffect(appeared ? 1 : 0.9)
                    Text("現在")
                        .font(.system(size: 10.5, weight: .bold, design: .rounded))
                        .foregroundColor(AppColor.primary)
                }
            }
            .frame(maxWidth: .infinity)
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: appeared)

            Text("風格沒有好壞，這只是現在的你的樣子")
                .font(.system(size: 12, design: .rounded))
                .foregroundColor(AppColor.inkTertiary)

            Rectangle()
                .fill(Color(hex: "F0EDE5"))
                .frame(height: 1)

            // 指標變化列(箭頭不帶褒貶色,一律中性 amber 表方向)
            VStack(spacing: 10) {
                metricShiftRow(name: "持股檔數",
                               old: previous.map { Double($0.portfolioMetrics.holdingCount) },
                               new: Double(current.portfolioMetrics.holdingCount),
                               format: { "\(Int($0)) 檔" })
                metricShiftRow(name: "最大持股集中度",
                               old: previous?.portfolioMetrics.topHoldingWeight,
                               new: current.portfolioMetrics.topHoldingWeight,
                               format: { String(format: "%.1f%%", $0) })
                metricShiftRow(name: "近 30 日調整",
                               old: previous.map { Double($0.portfolioMetrics.activityCount30d) },
                               new: Double(current.portfolioMetrics.activityCount30d),
                               format: { "\(Int($0)) 次" })
                metricShiftRow(name: "科技類占比",
                               old: previous?.portfolioMetrics.techWeight,
                               new: current.portfolioMetrics.techWeight,
                               format: { String(format: "%.1f%%", $0) })
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(AppColor.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Color(hex: "786446").opacity(0.06), radius: 9, x: 0, y: 6)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { appeared = true }
        }
    }

    @ViewBuilder
    private func metricShiftRow(name: String, old: Double?, new: Double, format: (Double) -> String) -> some View {
        HStack {
            Text(name)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(AppColor.inkPrimary)
            Spacer()
            if let old, abs(old - new) > 0.05 {
                HStack(spacing: 5) {
                    Text(format(old))
                        .foregroundColor(AppColor.inkQuaternary)
                    Image(systemName: new > old ? "arrow.up.right" : "arrow.down.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(AppColor.amberNumber)
                    Text(format(new))
                        .foregroundColor(AppColor.inkPrimary)
                        .fontWeight(.bold)
                }
                .font(.system(size: 12.5, design: .rounded))
                .monospacedDigit()
            } else {
                Text("\(format(new)) · 不變")
                    .font(.system(size: 12.5, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(AppColor.inkTertiary)
            }
        }
    }
}

// MARK: - 16e 時間軸卡(最近快照)

struct StyleTimelineCard: View {
    let snapshots: [HabitSnapshotRead]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("最近的紀錄")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .kerning(2)
                .foregroundColor(AppColor.inkTertiary)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(snapshots.enumerated()), id: \.element.id) { index, snapshot in
                    HStack(alignment: .top, spacing: 12) {
                        // 圓點 + 連線(當前點掛光環)
                        VStack(spacing: 0) {
                            ZStack {
                                if index == 0 {
                                    Circle()
                                        .fill(AppColor.primary.opacity(0.2))
                                        .frame(width: 18, height: 18)
                                }
                                Circle()
                                    .fill(index == 0 ? AppColor.primary : Color(hex: "D8D4C8"))
                                    .frame(width: 10, height: 10)
                            }
                            if index < snapshots.count - 1 {
                                Rectangle()
                                    .fill(Color(hex: "D8D4C8"))
                                    .frame(width: 2)
                                    .frame(minHeight: 34)
                            }
                        }
                        .frame(width: 18)

                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 8) {
                                Text(snapshot.createdAt.formatted(.dateTime.year().month().day()))
                                    .font(.system(size: 11, design: .rounded))
                                    .monospacedDigit()
                                    .foregroundColor(AppColor.inkQuaternary)
                                Text(snapshot.observedStyle.label)
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                                    .foregroundColor(index == 0 ? AppColor.primary : AppColor.inkSecondary)
                            }
                            Text(snapshot.changeSummary)
                                .font(.system(size: 11.5, design: .rounded))
                                .foregroundColor(AppColor.inkTertiary)
                                .lineSpacing(4)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.bottom, index < snapshots.count - 1 ? 14 : 0)
                    }
                }
            }
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColor.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Color(hex: "786446").opacity(0.06), radius: 9, x: 0, y: 6)
    }
}
