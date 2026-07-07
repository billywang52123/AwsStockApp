import SwiftUI

// MARK: - 9b 加碼 / 9c 賣出 / 覆蓋 輸入頁(spec 04)
// TradeInputCard(股數・價格輸入 + 快選 chips)+ MergePreviewCard(即時預覽)

struct TradeUpdateView: View {
    @StateObject private var viewModel: TradeUpdateViewModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: String?
    @State private var showOverrideConfirm = false
    /// 更新完成後由父層刷新持股
    let onDone: () -> Void

    init(intent: HoldingUpdateIntent, holding: Holding, onDone: @escaping () -> Void) {
        self._viewModel = StateObject(wrappedValue: TradeUpdateViewModel(intent: intent, holding: holding))
        self.onDone = onDone
    }

    private var holding: Holding { viewModel.holding }

    var body: some View {
        ZStack(alignment: .bottom) {
            AppColor.background.edgesIgnoringSafeArea(.all)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    header

                    if holding.lots.count > 1 {
                        brokerPicker.padding(.top, 14)
                    }

                    sharesCard.padding(.top, 20)

                    if viewModel.intent != .override {
                        priceCard.padding(.top, 12)
                    }

                    previewSection.padding(.top, 16)

                    if let error = viewModel.errorMessage {
                        Text(error)
                            .font(.system(size: 12, design: .rounded))
                            .foregroundColor(AppColor.roseStrong)
                            .padding(.top, 10)
                    }

                    ctaButton.padding(.top, 20)

                    DisclaimerView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 16)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
            .scrollDismissesKeyboard(.interactively)

            if viewModel.showUndoToast {
                undoToast
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.25), value: viewModel.showUndoToast)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("完成") { focusedField = nil }
                    .font(.system(.body, design: .rounded))
                    .fontWeight(.bold)
                    .foregroundColor(AppColor.primary)
            }
        }
        .onAppear {
            Task { await viewModel.loadTodayPrice() }
        }
        .confirmationDialog(
            "確定改成 \(viewModel.shares.formatted()) 股?",
            isPresented: $showOverrideConfirm,
            titleVisibility: .visible
        ) {
            Button("確定,以最新庫存為準", role: .destructive) {
                Task { if await viewModel.submit() { finish() } }
            }
            Button("取消", role: .cancel) {}
        } message: {
            let diff = viewModel.previewTotalShares - holding.totalShares
            Text("目前紀錄 \(holding.totalShares.formatted()) 股,差異 \(diff >= 0 ? "+" : "")\(diff.formatted()) 股;均價會保留不變。")
        }
    }

    // MARK: - Header

    private var titleText: String {
        switch viewModel.intent {
        case .buy: return "記錄加買"
        case .sell: return "記錄賣出"
        case .override: return "覆蓋為最新庫存"
        }
    }

    private var pillColors: (fg: Color, bg: Color) {
        switch viewModel.intent {
        case .buy: return (AppColor.upText, Color(hex: "F5EAEA"))
        case .sell, .override: return (AppColor.downText, Color(hex: "EAF2EC"))
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text(titleText)
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                    .foregroundColor(AppColor.inkPrimary)

                Text("\(holding.name) \(holding.symbol)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(pillColors.fg)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 12)
                    .background(pillColors.bg)
                    .clipShape(Capsule())
            }

            Text("目前 \(holding.totalShares.formatted()) 股\(currentAvgText)")
                .font(.system(size: 13, design: .rounded).monospacedDigit())
                .foregroundColor(AppColor.inkTertiary)
        }
        .padding(.top, 8)
    }

    private var currentAvgText: String {
        guard let avg = holding.avgPrice else { return " · 尚未填買價" }
        return " · 均價 \(avg.trimmedString)"
    }

    // MARK: - 多券商帳戶選擇

    private var brokerPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("異動哪個券商帳戶")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(AppColor.inkQuaternary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if viewModel.intent == .sell {
                        brokerChip(label: "全部帳戶", broker: nil)
                    }
                    ForEach(holding.lots) { lot in
                        brokerChip(label: "\(lot.brokerDisplayName) \(lot.shares.formatted()) 股", broker: lot.broker)
                    }
                }
            }
        }
    }

    private func brokerChip(label: String, broker: String?) -> some View {
        let selected = viewModel.selectedBroker == broker
        return Button {
            viewModel.selectedBroker = broker
            HapticManager.shared.triggerSelection()
        } label: {
            Text(label)
                .font(.system(size: 12, weight: selected ? .bold : .semibold, design: .rounded))
                .foregroundColor(selected ? Color(hex: "5B5FA8") : AppColor.inkSecondary)
                .padding(.vertical, 6)
                .padding(.horizontal, 14)
                .background(selected ? Color(hex: "EEEEFA") : AppColor.bgTrack)
                .overlay(Capsule().stroke(selected ? AppColor.primary : Color.clear, lineWidth: 1.5))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 股數卡

    private var sharesCard: some View {
        inputCard(
            label: viewModel.intent == .override ? "最新總股數" : "這次的股數",
            unit: "股",
            text: $viewModel.sharesText,
            keyboard: .numberPad,
            focusKey: "shares"
        ) {
            if viewModel.intent == .sell {
                sellRatioChips
            } else {
                buyQuickChips
            }
        }
    }

    private var buyQuickChips: some View {
        HStack(spacing: 8) {
            ForEach([("+100", 100), ("+500", 500), ("+1 張", 1000), ("+10 零股", 10)], id: \.0) { chip in
                Button { viewModel.applyBuyChip(chip.1) } label: {
                    Text(chip.0)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(AppColor.inkSecondary)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 14)
                        .background(AppColor.bgTrack)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var sellRatioChips: some View {
        HStack(spacing: 8) {
            ForEach([("1/6", 1.0 / 6), ("1/4", 0.25), ("一半", 0.5), ("全部", 1.0)], id: \.0) { chip in
                let target = chip.1 >= 1 ? holding.totalShares : Int((Double(holding.totalShares) * chip.1).rounded())
                let selected = viewModel.shares == target && viewModel.shares > 0
                Button { viewModel.applySellRatio(chip.1) } label: {
                    Text(chip.0)
                        .font(.system(size: 12, weight: selected ? .bold : .semibold, design: .rounded))
                        .foregroundColor(selected ? AppColor.downText : AppColor.inkSecondary)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 14)
                        .background(selected ? Color(hex: "EAF2EC") : AppColor.bgTrack)
                        .overlay(Capsule().stroke(selected ? AppColor.downText : Color.clear, lineWidth: 1.5))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - 價格卡

    private var priceCard: some View {
        inputCard(
            label: viewModel.intent == .buy ? "這次的買價" : "這次的賣價",
            unit: "元",
            text: $viewModel.priceText,
            keyboard: .decimalPad,
            focusKey: "price",
            disabled: viewModel.sharesOnlyMode,
            topRight: viewModel.todayPrice.map { "今日成交價 \($0.trimmedString)" }
        ) {
            if viewModel.intent == .buy {
                Button {
                    viewModel.sharesOnlyMode.toggle()
                    if viewModel.sharesOnlyMode {
                        viewModel.priceText = ""
                        focusedField = nil
                    }
                    HapticManager.shared.triggerSelection()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: viewModel.sharesOnlyMode ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 13))
                        Text("不記得買價?先只填股數,均價維持不變")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                    }
                    .foregroundColor(AppColor.primary)
                }
                .buttonStyle(.plain)
            } else if viewModel.price == nil {
                Text("先不填也可以,只是無法幫你算這筆已實現損益")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundColor(AppColor.inkQuaternary)
            }
        }
    }

    @ViewBuilder
    private func inputCard<Extra: View>(
        label: String,
        unit: String,
        text: Binding<String>,
        keyboard: UIKeyboardType,
        focusKey: String,
        disabled: Bool = false,
        topRight: String? = nil,
        @ViewBuilder extra: () -> Extra
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(label)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(AppColor.inkQuaternary)
                Spacer()
                if let topRight {
                    Text(topRight)
                        .font(.system(size: 11, design: .rounded).monospacedDigit())
                        .foregroundColor(AppColor.inkFaint)
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                TextField("0", text: text)
                    .keyboardType(keyboard)
                    .focused($focusedField, equals: focusKey)
                    .font(.system(size: 34, weight: .heavy, design: .rounded).monospacedDigit())
                    .foregroundColor(disabled ? AppColor.inkFaint : AppColor.inkPrimary)
                    .disabled(disabled)

                Text(unit)
                    .font(.system(size: 15, design: .rounded))
                    .foregroundColor(AppColor.inkTertiary)
            }

            extra()
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 20)
        .background(Color.white)
        .cornerRadius(20)
        .shadow(color: Color(hex: "786446").opacity(0.06), radius: 9, x: 0, y: 6)
        .onTapGesture { if !disabled { focusedField = focusKey } }
    }

    // MARK: - 預覽

    @ViewBuilder
    private var previewSection: some View {
        switch viewModel.intent {
        case .buy: buyPreviewCard
        case .sell: sellPreviewCard
        case .override: overridePreviewCard
        }
    }

    /// 9b 攤平預覽紫卡 MergePreviewCard
    private var buyPreviewCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("加買後的持股")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.7))
                .kerning(1)

            HStack(spacing: 20) {
                previewColumn(
                    title: "總股數",
                    old: holding.totalShares.formatted(),
                    new: viewModel.previewTotalShares.formatted()
                )

                Rectangle()
                    .fill(Color.white.opacity(0.18))
                    .frame(width: 1, height: 44)

                if viewModel.sharesOnlyMode || viewModel.price == nil {
                    previewColumn(
                        title: "加權均價",
                        old: nil,
                        new: holding.avgPrice?.trimmedString ?? "—",
                        note: "未含此筆"
                    )
                } else {
                    previewColumn(
                        title: "加權均價",
                        old: holding.avgPrice?.trimmedString,
                        new: viewModel.previewAvgPrice?.trimmedString ?? "—"
                    )
                }
            }

            if let formula = viewModel.avgFormulaText {
                Text(formula)
                    .font(.system(size: 11, design: .rounded).monospacedDigit())
                    .foregroundColor(.white.opacity(0.65))
                    .lineSpacing(11 * 0.7)
            } else if viewModel.sharesOnlyMode {
                Text("這筆先不列入均價計算,之後可以在券商分帳補填買價。")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundColor(.white.opacity(0.65))
                    .lineSpacing(11 * 0.7)
            }
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
        .animation(.easeOut(duration: 0.25), value: viewModel.sharesText)
        .animation(.easeOut(duration: 0.25), value: viewModel.priceText)
    }

    private func previewColumn(title: String, old: String?, new: String, note: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, design: .rounded))
                .foregroundColor(.white.opacity(0.6))

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if let old, old != new {
                    Text(old)
                        .font(.system(size: 14, design: .rounded).monospacedDigit())
                        .strikethrough()
                        .foregroundColor(.white.opacity(0.55))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white.opacity(0.7))
                }
                Text(new)
                    .font(.system(size: 22, weight: .heavy, design: .rounded).monospacedDigit())
                    .foregroundColor(.white)
                if let note {
                    Text(note)
                        .font(.system(size: 11, design: .rounded))
                        .foregroundColor(.white.opacity(0.6))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 9c 賣出預覽白卡 + RealizedPnLBox
    private var sellPreviewCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("剩餘股數")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundColor(AppColor.inkQuaternary)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        if viewModel.shares > 0 {
                            Text(holding.totalShares.formatted())
                                .font(.system(size: 14, design: .rounded).monospacedDigit())
                                .strikethrough()
                                .foregroundColor(AppColor.inkFaint)
                            Image(systemName: "arrow.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(AppColor.inkQuaternary)
                        }
                        Text(viewModel.previewTotalShares.formatted())
                            .font(.system(size: 22, weight: .heavy, design: .rounded).monospacedDigit())
                            .foregroundColor(AppColor.inkPrimary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 6) {
                    Text("加權均價")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundColor(AppColor.inkQuaternary)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(holding.avgPrice?.trimmedString ?? "—")
                            .font(.system(size: 22, weight: .heavy, design: .rounded).monospacedDigit())
                            .foregroundColor(AppColor.inkPrimary)
                        Text("不變")
                            .font(.system(size: 11, design: .rounded))
                            .foregroundColor(AppColor.inkQuaternary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let pnl = viewModel.previewRealizedPnl {
                realizedPnlBox(pnl: pnl, percent: viewModel.previewRealizedPnlPercent)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            Text(viewModel.isSellAll
                 ? "全部賣出後會移到「已出場」,紀錄都會保留,之後也可以還原。"
                 : "賣出不會動到你的均價;之後回頭看,這筆的結果都算好了。")
                .font(.system(size: 11, design: .rounded))
                .foregroundColor(AppColor.inkQuaternary)
                .lineSpacing(11 * 0.7)
        }
        .padding(.vertical, 20)
        .padding(.horizontal, 22)
        .background(Color.white)
        .cornerRadius(22)
        .shadow(color: Color(hex: "786446").opacity(0.10), radius: 13, x: 0, y: 10)
        .animation(.easeOut(duration: 0.25), value: viewModel.sharesText)
        .animation(.easeOut(duration: 0.25), value: viewModel.priceText)
    }

    private func realizedPnlBox(pnl: Double, percent: Double?) -> some View {
        let isGain = pnl >= 0
        let mainColor = isGain ? AppColor.upText : AppColor.downText
        let bgColor = isGain ? Color(hex: "FBF1F1") : Color(hex: "EFF6F1")
        let pillBg = isGain ? Color(hex: "F5EAEA") : Color(hex: "EAF2EC")

        return HStack {
            Text("這筆已實現損益")
                .font(.system(size: 12, design: .rounded))
                .foregroundColor(AppColor.inkTertiary)

            Spacer()

            Text("\(isGain ? "+" : "")\(pnl.formatted(.number.precision(.fractionLength(0))))")
                .font(.system(size: 17, weight: .heavy, design: .rounded).monospacedDigit())
                .foregroundColor(mainColor)

            if let percent {
                Text("\(isGain ? "+" : "")\(percent.formatted(.number.precision(.fractionLength(1))))%")
                    .font(.system(size: 12, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundColor(mainColor)
                    .padding(.vertical, 3)
                    .padding(.horizontal, 8)
                    .background(pillBg)
                    .clipShape(Capsule())
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(bgColor)
        .cornerRadius(14)
    }

    /// 覆蓋預覽:舊 → 新 + 差額
    private var overridePreviewCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("覆蓋後的持股")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(AppColor.inkQuaternary)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(holding.totalShares.formatted())
                    .font(.system(size: 14, design: .rounded).monospacedDigit())
                    .strikethrough()
                    .foregroundColor(AppColor.inkFaint)
                Image(systemName: "arrow.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppColor.inkQuaternary)
                Text("\(viewModel.previewTotalShares.formatted()) 股")
                    .font(.system(size: 22, weight: .heavy, design: .rounded).monospacedDigit())
                    .foregroundColor(AppColor.inkPrimary)

                if viewModel.shares > 0 {
                    let diff = viewModel.previewTotalShares - holding.totalShares
                    Text("\(diff >= 0 ? "+" : "")\(diff.formatted())")
                        .font(.system(size: 11, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundColor(diff >= 0 ? AppColor.downText : AppColor.upText)
                        .padding(.vertical, 3)
                        .padding(.horizontal, 8)
                        .background(diff >= 0 ? Color(hex: "EAF2EC") : Color(hex: "F5EAEA"))
                        .clipShape(Capsule())
                }
            }

            Text("均價保留不變;適合把紀錄對回券商 App 上的最新庫存。")
                .font(.system(size: 11, design: .rounded))
                .foregroundColor(AppColor.inkQuaternary)
                .lineSpacing(11 * 0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 20)
        .padding(.horizontal, 22)
        .background(Color.white)
        .cornerRadius(22)
        .shadow(color: Color(hex: "786446").opacity(0.10), radius: 13, x: 0, y: 10)
        .animation(.easeOut(duration: 0.25), value: viewModel.sharesText)
    }

    // MARK: - CTA

    private var ctaText: String {
        let n = viewModel.shares
        switch viewModel.intent {
        case .buy:
            return n > 0 ? "確認記錄加買 \(n.formatted()) 股" : "確認記錄加買"
        case .sell:
            if viewModel.isSellAll { return "全部賣出,移至已出場" }
            return n > 0 ? "確認記錄賣出 \(n.formatted()) 股" : "確認記錄賣出"
        case .override:
            return n > 0 ? "覆蓋為 \(n.formatted()) 股" : "覆蓋為最新庫存"
        }
    }

    private var ctaColor: Color {
        viewModel.intent == .sell ? AppColor.downText : AppColor.primary
    }

    private var ctaButton: some View {
        Button {
            focusedField = nil
            if viewModel.intent == .override {
                showOverrideConfirm = true
            } else {
                Task { if await viewModel.submit() { finish() } }
            }
        } label: {
            Group {
                if viewModel.isSubmitting {
                    ProgressView().tint(.white)
                } else {
                    Text(ctaText)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                }
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(ctaColor)
            .cornerRadius(18)
            .shadow(color: ctaColor.opacity(0.35), radius: 13, x: 0, y: 10)
        }
        .disabled(!viewModel.canSubmit)
        .opacity(viewModel.canSubmit ? 1 : 0.4)
    }

    // MARK: - Undo toast(全部賣出後 5 秒可還原)

    private var undoToast: some View {
        HStack(spacing: 12) {
            Text("\(holding.name) 已移至「已出場」")
                .font(.system(size: 13, design: .rounded))
                .foregroundColor(.white)

            Spacer()

            Button {
                Task {
                    if await viewModel.undoSellAll() { finish() }
                }
            } label: {
                Text("還原")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(Color(hex: "C4C7EE"))
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 4)
        .background(AppColor.inkPrimary.opacity(0.94))
        .cornerRadius(16)
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
        .task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            if viewModel.showUndoToast { finish() }
        }
    }

    private func finish() {
        onDone()
        dismiss()
    }
}
