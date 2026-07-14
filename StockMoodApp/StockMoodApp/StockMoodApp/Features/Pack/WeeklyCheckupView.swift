import SwiftUI

// MARK: - 15k · 週末體檢回顧頁 `WeeklyCheckupView`
// AI 本週誠實度:上週提醒 → 本週對帳;說中沒說中都照實呈現(未發生不用紅色)

struct WeeklyCheckupView: View {
    @State private var checkup: WeeklyCheckup?
    @State private var hasError = false
    @State private var activeChip: SourceChip?
    @State private var barGrown = false

    var body: some View {
        ZStack {
            AppColor.background.ignoresSafeArea()

            if let checkup {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        // 頁頭
                        Text(checkup.weekLabel)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(AppColor.inkQuaternary)
                        Text("週末體檢")
                            .font(.system(size: 26, weight: .heavy, design: .rounded))
                            .foregroundColor(AppColor.inkPrimary)
                            .padding(.top, 4)

                        specialPackBanner(checkup: checkup)
                            .padding(.top, 18)

                        honestyCard(checkup: checkup)
                            .padding(.top, 16)

                        checkupTiles(checkup: checkup)
                            .padding(.top, 16)

                        // footer 置於內容流末端(此頁可捲動,不可釘底)
                        DisclaimerBlock(text: "本內容為現況描述與風險提示,非投資建議")
                            .padding(.top, 26)
                            .padding(.bottom, 24)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
                }
            } else if hasError {
                VStack(spacing: 10) {
                    Text("體檢報告暫時拿不到")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(AppColor.inkSecondary)
                    Text("網路恢復後再試一次就好")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundColor(AppColor.inkTertiary)
                }
            } else {
                ProgressView().tint(AppColor.primary)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $activeChip) { chip in
            SourceChipSheet(chip: chip) { activeChip = nil }
        }
        .task {
            do {
                checkup = try await DependencyContainer.shared.packService.getWeeklyCheckup()
                // 誠實度分段進度條:首次出現由左至右長出 0.6s
                withAnimation(.easeOut(duration: 0.6).delay(0.25)) { barGrown = true }
            } catch {
                hasError = true
                print("Load weekly checkup failed: \(error)")
            }
        }
    }

    // ── 本週特別卡包 banner(135° 漸層 + 全息掃光) ──

    private func specialPackBanner(checkup: WeeklyCheckup) -> some View {
        HStack(spacing: 14) {
            // 禮物圖示格(dashed 邊)
            Text("🎁")
                .font(.system(size: 26))
                .frame(width: 52, height: 70)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.6),
                                      style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                )

            VStack(alignment: .leading, spacing: 5) {
                Text("本週特別卡包已送達")
                    .font(.system(size: 14.5, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text(checkup.specialPackNote)
                    .font(.system(size: 11.5, design: .rounded))
                    .foregroundColor(.white.opacity(0.85))
                    .lineSpacing(4)
            }

            Spacer()

            Text("拆開")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(AppColor.gradientCardBottom)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Color.white)
                .clipShape(Capsule())
        }
        .padding(16)
        .background(
            LinearGradient(colors: [AppColor.gradientCardTop, AppColor.gradientCardBottom],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .holoShimmer(widthFraction: 0.4, duration: 4.5, opacity: 0.25)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: AppColor.gradientCardBottom.opacity(0.35), radius: 16, x: 0, y: 10)
    }

    // ── AI 本週誠實度卡 `HonestyScoreCard` ──

    private func honestyCard(checkup: WeeklyCheckup) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("AI 本週誠實度")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(AppColor.inkPrimary)
                Spacer()
                Text("上週提醒 → 本週對帳")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundColor(AppColor.inkQuaternary)
            }

            // 巨型比分 + 分段進度條
            HStack(alignment: .center, spacing: 14) {
                HStack(alignment: .lastTextBaseline, spacing: 2) {
                    Text("\(checkup.metCount)")
                        .font(.system(size: 30, weight: .heavy, design: .monospaced))
                        .foregroundColor(AppColor.inkPrimary)
                    Text("/\(checkup.totalCount)")
                        .font(.system(size: 16, design: .monospaced))
                        .foregroundColor(AppColor.inkQuaternary)
                }

                GeometryReader { geo in
                    let metRatio = checkup.totalCount > 0
                        ? CGFloat(checkup.metCount) / CGFloat(checkup.totalCount) : 0
                    HStack(spacing: 3) {
                        Capsule()
                            .fill(TrustCardColor.honestyMet)
                            .frame(width: max(0, geo.size.width * metRatio - 1.5))
                        Capsule()
                            .fill(TrustCardColor.honestyMiss)
                    }
                    .scaleEffect(x: barGrown ? 1 : 0.02, anchor: .leading)
                }
                .frame(height: 8)
            }

            Text("\(checkup.totalCount) 項提醒 · \(checkup.metCount) 項應驗 · \(checkup.totalCount - checkup.metCount) 項未發生")
                .font(.system(size: 12, design: .rounded))
                .foregroundColor(AppColor.inkTertiary)

            // 對帳列(照實呈現;未發生列不用紅色,維持安撫語氣)
            VStack(spacing: 10) {
                ForEach(checkup.rows) { row in
                    ReconciliationRowView(row: row) { activeChip = $0 }
                }
            }

            Text("說中或沒說中,都照實記錄——AI 的可信度由對帳結果累積,不由話術。")
                .font(.system(size: 10.5, design: .rounded))
                .foregroundColor(AppColor.inkFaint)
                .lineSpacing(6)
        }
        .padding(18)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: Color(red: 120/255, green: 100/255, blue: 70/255).opacity(0.10),
                radius: 14, x: 0, y: 8)
    }

    // ── 本週組合體檢卡(兩欄小卡) ──

    private func checkupTiles(checkup: WeeklyCheckup) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("本週組合體檢")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(AppColor.inkPrimary)

            HStack(spacing: 12) {
                ForEach(checkup.tiles) { tile in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(tile.label)
                            .font(.system(size: 11, design: .rounded))
                            .foregroundColor(AppColor.inkTertiary)
                        Text(tile.value)
                            .font(.system(size: 15, weight: .heavy, design: .monospaced))
                            .foregroundColor(AppColor.inkPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Text(tile.note)
                            .font(.system(size: 10.5, design: .rounded))
                            .foregroundColor(AppColor.inkQuaternary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(AppColor.bgInset)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
        }
        .padding(18)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: Color(red: 120/255, green: 100/255, blue: 70/255).opacity(0.10),
                radius: 14, x: 0, y: 8)
    }
}

// MARK: - 對帳列 `ReconciliationRow`(✓ 應驗 / ✕ 未發生)

struct ReconciliationRowView: View {
    let row: ReconciliationRow
    let onChip: (SourceChip) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: row.isMet ? "checkmark" : "xmark")
                .font(.system(size: 10, weight: .heavy))
                .foregroundColor(.white)
                .frame(width: 22, height: 22)
                .background(row.isMet ? TrustCardColor.honestyMet : TrustCardColor.honestyMiss)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 6) {
                Text("「\(row.statement)」→ \(row.isMet ? "應驗" : "未發生")")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(AppColor.inkPrimary)
                    .lineSpacing(5)
                Text(row.note)
                    .font(.system(size: 11.5, design: .rounded))
                    .foregroundColor(AppColor.inkSecondary)
                    .lineSpacing(6)
                if let chip = row.chip {
                    SourceChipView(chip: chip, onTap: onChip)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(row.isMet ? TrustCardColor.metRowBg : TrustCardColor.missRowBg)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
