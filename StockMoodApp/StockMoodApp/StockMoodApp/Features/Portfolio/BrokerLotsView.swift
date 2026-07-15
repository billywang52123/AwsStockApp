import SwiftUI

// MARK: - 9e · 個股券商分帳 BrokerLotRow + ActivityLogRow(spec 04)

struct BrokerLotsView: View {
    @StateObject private var viewModel: BrokerLotsViewModel
    @State private var editingLot: BrokerLot?
    @State private var showAddLot = false
    @State private var lotPendingDelete: BrokerLot?
    /// 分帳有異動時讓父層刷新
    var onChanged: (() -> Void)? = nil

    init(symbol: String, holding: Holding? = nil, onChanged: (() -> Void)? = nil) {
        self._viewModel = StateObject(wrappedValue: BrokerLotsViewModel(symbol: symbol, holding: holding))
        self.onChanged = onChanged
    }

    /// 分帳列左色條:第 1 帳 → 第 2 帳 → 依序淡化
    private static let lotBarColors: [Color] = [
        Color(hex: "7B7FD4"), Color(hex: "C4C7EE"), Color(hex: "E0E1F5"), Color(hex: "EDEEF9"),
    ]

    var body: some View {
        ZStack {
            AppColor.background.edgesIgnoringSafeArea(.all)

            if viewModel.isLoading {
                ProgressView("正在整理券商分帳...")
            } else if let holding = viewModel.holding {
                content(holding)
            } else {
                EmptyStateView(
                    title: "找不到這檔持股",
                    message: viewModel.errorMessage ?? "這檔可能已全部賣出或被移除。",
                    buttonTitle: "重新整理"
                ) {
                    Task { await viewModel.load() }
                }
            }
        }
        .navigationTitle("券商分帳")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            Task { await viewModel.load() }
        }
        .sheet(item: $editingLot) { lot in
            LotEditSheet(
                title: "編輯 \(lot.brokerDisplayName)",
                broker: lot.broker ?? "",
                shares: lot.shares,
                price: lot.avgPrice
            ) { broker, shares, price in
                Task {
                    if await viewModel.updateLot(lot, broker: broker, shares: shares, price: price) {
                        onChanged?()
                    }
                }
            }
        }
        .sheet(isPresented: $showAddLot) {
            LotEditSheet(title: "新增券商帳戶", broker: "", shares: 0, price: nil) { broker, shares, price in
                Task {
                    if await viewModel.addLot(broker: broker, shares: shares, price: price) {
                        onChanged?()
                    }
                }
            }
        }
        .confirmationDialog(
            "刪除這個分帳?",
            isPresented: Binding(
                get: { lotPendingDelete != nil },
                set: { if !$0 { lotPendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("刪除 \(lotPendingDelete?.brokerDisplayName ?? "")(\(lotPendingDelete?.shares.formatted() ?? "0") 股)", role: .destructive) {
                if let lot = lotPendingDelete {
                    Task {
                        await viewModel.deleteLot(lot)
                        onChanged?()
                    }
                }
                lotPendingDelete = nil
            }
            Button("取消", role: .cancel) { lotPendingDelete = nil }
        } message: {
            Text("只會刪掉 App 內這個券商的紀錄,總股數與均價會重新計算。")
        }
    }

    // MARK: - 主內容

    private func content(_ holding: Holding) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                header(holding)

                mergedCard(holding).padding(.top, 18)

                Text("各券商帳戶")
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundColor(AppColor.inkPrimary)
                    .padding(.top, 16)

                VStack(spacing: 11) {
                    ForEach(Array(sortedLots(holding).enumerated()), id: \.element.id) { index, lot in
                        lotRow(lot, index: index)
                    }
                    addLotRow
                }
                .padding(.top, 10)

                if !viewModel.activities.isEmpty {
                    activityCard.padding(.top, 16)
                }

                if let error = viewModel.errorMessage, viewModel.holding != nil {
                    Text(error)
                        .font(.system(size: 12, design: .rounded))
                        .foregroundColor(AppColor.roseStrong)
                        .padding(.top, 10)
                }

                DisclaimerView()
                    .frame(maxWidth: .infinity)
                    .padding(.top, 16)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
    }

    private func sortedLots(_ holding: Holding) -> [BrokerLot] {
        holding.lots.sorted { $0.shares > $1.shares }
    }

    private func header(_ holding: Holding) -> some View {
        let style = IndustryStyle.style(for: holding.industry ?? "")
        return HStack(spacing: 12) {
            ZStack {
                Circle().fill(style.avatarBg).frame(width: 46, height: 46)
                Text(String(holding.name.prefix(1)))
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(style.color)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(holding.name)
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                    .foregroundColor(AppColor.inkPrimary)
                Text("\(holding.symbol)\(holding.industry.map { " · \($0)" } ?? "") · \(holding.lots.count) 個券商帳戶")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundColor(AppColor.inkQuaternary)
            }
            Spacer()
        }
        .padding(.top, 8)
    }

    // MARK: - 合併持股紫卡

    private func mergedCard(_ holding: Holding) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("合併持股")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.7))
                .kerning(1)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(holding.totalShares.formatted())
                    .font(.system(size: 32, weight: .heavy, design: .rounded).monospacedDigit())
                    .foregroundColor(.white)
                Text("股")
                    .font(.system(size: 14, design: .rounded))
                    .foregroundColor(.white.opacity(0.7))

                Spacer()

                Text("加權均價")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundColor(.white.opacity(0.6))
                Text(holding.avgPrice?.trimmedString ?? "—")
                    .font(.system(size: 22, weight: .heavy, design: .rounded).monospacedDigit())
                    .foregroundColor(.white)
            }
            .sensitiveAmount()

            // 分帳占比 bar
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(Array(sortedLots(holding).enumerated()), id: \.element.id) { index, lot in
                        Capsule()
                            .fill(Color.white.opacity(index == 0 ? 0.85 : max(0.40 - Double(index - 1) * 0.12, 0.15)))
                            .frame(width: max(geo.size.width * viewModel.share(of: lot) - 2, 4))
                    }
                }
            }
            .frame(height: 10)

            if holding.avgPriceIncomplete {
                Text("有分帳還沒填買價,均價先以已填的部分加權;補填後會更準。")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundColor(Color(hex: "FFE3B8"))
                    .lineSpacing(11 * 0.7)
            }

            Text("分析、焦慮分數與 AI 觀點,都用這個合併後的數字計算")
                .font(.system(size: 11, design: .rounded))
                .foregroundColor(.white.opacity(0.65))
        }
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
    }

    // MARK: - 分帳列

    private func lotRow(_ lot: BrokerLot, index: Int) -> some View {
        Button {
            editingLot = lot
        } label: {
            HStack(spacing: 14) {
                Capsule()
                    .fill(Self.lotBarColors[min(index, Self.lotBarColors.count - 1)])
                    .frame(width: 10, height: 38)

                VStack(alignment: .leading, spacing: 2) {
                    Text(lot.brokerDisplayName)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(AppColor.inkPrimary)
                    Text("上次更新 \(lot.updatedAt.formatted(.dateTime.month().day())) · \(lot.source == "import" ? "截圖匯入" : "手動")")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundColor(AppColor.inkQuaternary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(lot.shares.formatted()) 股")
                        .font(.system(size: 15, weight: .heavy, design: .rounded).monospacedDigit())
                        .foregroundColor(AppColor.inkPrimary)
                    Text(lot.avgPrice.map { "均價 \($0.trimmedString)" } ?? "未填買價")
                        .font(.system(size: 11, design: .rounded).monospacedDigit())
                        .foregroundColor(lot.avgPrice == nil ? AppColor.amberStrong : AppColor.inkQuaternary)
                }
                .sensitiveAmount()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(AppColor.inkFaint)
            }
            .padding(.vertical, 15)
            .padding(.horizontal, 18)
            .background(Color.white)
            .cornerRadius(18)
            .shadow(color: Color(hex: "786446").opacity(0.06), radius: 9, x: 0, y: 6)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                lotPendingDelete = lot
            } label: {
                Label("刪除這個分帳", systemImage: "trash")
            }
        }
    }

    private var addLotRow: some View {
        Button {
            showAddLot = true
        } label: {
            Text("+ 新增券商帳戶")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(AppColor.inkTertiary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Color(hex: "D5D0C4"), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - 最近異動卡

    private var activityCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("最近異動")
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundColor(AppColor.inkPrimary)

            VStack(spacing: 9) {
                ForEach(viewModel.activities) { activity in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(BrokerLotsViewModel.activityDotColor(activity))
                            .frame(width: 7, height: 7)

                        Text(BrokerLotsViewModel.activityDescription(activity))
                            .font(.system(size: 12, design: .rounded).monospacedDigit())
                            .foregroundColor(AppColor.inkSecondary)
                            .lineLimit(1)

                        Spacer()

                        Text(activityTrailing(activity))
                            .font(.system(size: 12, design: .rounded).monospacedDigit())
                            .foregroundColor(AppColor.inkQuaternary)
                    }
                    .contextMenu {
                        Button(role: .destructive) {
                            if let index = viewModel.activities.firstIndex(of: activity) {
                                Task {
                                    await viewModel.deleteActivity(at: IndexSet(integer: index))
                                    onChanged?()
                                }
                            }
                        } label: {
                            Label("刪除這筆異動(會回算均價)", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 18)
        .background(Color.white)
        .cornerRadius(18)
        .shadow(color: Color(hex: "786446").opacity(0.06), radius: 9, x: 0, y: 6)
    }

    private func activityTrailing(_ activity: HoldingActivity) -> String {
        if let pnl = activity.realizedPnl {
            return "\(pnl >= 0 ? "+" : "")\(pnl.formatted(.number.precision(.fractionLength(0))))"
        }
        if let avg = activity.avgPriceAfter {
            return "均價 \(avg.trimmedString)"
        }
        return activity.createdAt.formatted(.dateTime.month().day())
    }
}

// MARK: - 分帳編輯/新增 sheet

private struct LotEditSheet: View {
    let title: String
    @State var broker: String
    @State private var sharesText: String
    @State private var priceText: String
    let onSave: (String, Int, Double?) -> Void
    @Environment(\.dismiss) private var dismiss

    init(title: String, broker: String, shares: Int, price: Double?,
         onSave: @escaping (String, Int, Double?) -> Void) {
        self.title = title
        self._broker = State(initialValue: broker)
        self._sharesText = State(initialValue: shares > 0 ? String(shares) : "")
        self._priceText = State(initialValue: price.map { $0.trimmedString } ?? "")
        self.onSave = onSave
    }

    private var shares: Int { Int(sharesText.filter(\.isNumber)) ?? 0 }
    private var canSave: Bool { !broker.trimmingCharacters(in: .whitespaces).isEmpty && shares > 0 }

    var body: some View {
        NavigationView {
            ZStack {
                AppColor.background.edgesIgnoringSafeArea(.all)

                VStack(alignment: .leading, spacing: 16) {
                    // 券商快選
                    VStack(alignment: .leading, spacing: 8) {
                        Text("券商")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundColor(AppColor.inkQuaternary)

                        TextField("例如 富邦證券", text: $broker)
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(AppColor.inkPrimary)
                            .padding(12)
                            .background(Color.white)
                            .cornerRadius(12)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(TaiwanBrokers.common, id: \.self) { name in
                                    Button {
                                        broker = name
                                        HapticManager.shared.triggerSelection()
                                    } label: {
                                        Text(name)
                                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                                            .foregroundColor(broker == name ? Color(hex: "5B5FA8") : AppColor.inkSecondary)
                                            .padding(.vertical, 6)
                                            .padding(.horizontal, 12)
                                            .background(broker == name ? Color(hex: "EEEEFA") : AppColor.bgTrack)
                                            .clipShape(Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }

                    HStack(spacing: 12) {
                        editorField(label: "股數", placeholder: "例如 1000", keyboard: .numberPad, text: $sharesText)
                        editorField(label: "均價(可留空)", placeholder: "例如 900", keyboard: .decimalPad, text: $priceText)
                    }

                    Text("這裡填的是「這個券商帳戶」的最新數字,總覽會自動加權合併。")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundColor(AppColor.inkQuaternary)
                        .lineSpacing(11 * 0.7)

                    Spacer()

                    Button {
                        onSave(broker.trimmingCharacters(in: .whitespaces), shares, Double(priceText))
                        dismiss()
                    } label: {
                        Text("儲存")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background(AppColor.primary)
                            .cornerRadius(18)
                    }
                    .disabled(!canSave)
                    .opacity(canSave ? 1 : 0.4)
                }
                .padding(24)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { dismiss() }
                        .foregroundColor(AppColor.textSecondary)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func editorField(label: String, placeholder: String, keyboard: UIKeyboardType, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(AppColor.inkQuaternary)
            TextField(placeholder, text: text)
                .keyboardType(keyboard)
                .font(.system(size: 16, weight: .bold, design: .rounded).monospacedDigit())
                .padding(12)
                .background(Color.white)
                .cornerRadius(12)
        }
    }
}
