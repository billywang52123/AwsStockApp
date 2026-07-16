import SwiftUI

struct PortfolioInputView: View {
    @StateObject private var viewModel = PortfolioInputViewModel()
    @State private var showScanSheet = false
    @State private var showVoiceSheet = false
    @State private var showCustomBrokerInput = false
    @State private var customBrokerText = ""
    @FocusState private var focusedField: String?
    let onCompletion: ([String]) -> Void

    var body: some View {
        // Single scroll container + pinned bottom CTA: the keyboard resizes the
        // scroll area instead of crushing a fixed VStack (previous layout broke
        // apart whenever the number pad appeared)
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    Text("新增您的持股 (1~5檔)")
                        .font(.system(.title2, design: .serif))
                        .fontWeight(.bold)
                        .foregroundColor(AppColor.textPrimary)
                        .padding(.top, 30)

                    Text("輸入您持有的股票（例如：2330 台積電），或點擊下方拍照匯入對帳單。")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundColor(AppColor.textSecondary)

                    scanEntryCard

                    // 19a 語音卡:截圖匯入卡與手動輸入列之間(spec 08)
                    VoiceEntryCard { showVoiceSheet = true }
                        .padding(.top, 8)

                    searchBox

                    if !viewModel.selectedStocks.isEmpty {
                        selectedSection
                            .transition(.opacity)
                    }

                    resultsSection
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)

            // Pinned CTA
            if !viewModel.selectedStocks.isEmpty {
                // 10d 就地說明:第一次交出持股資料的當下講清楚
                TrustNote(text: viewModel.brokerRequired
                          ? "圖片辨識的券商不一定準確,請先選擇這批持股的來源券商"
                          : "只需要代號和股數,均價可以之後再補;不會要你連券商帳號")
                    .padding(.horizontal, 24)
                    .padding(.top, 6)

                AppButton(title: "確認持股", icon: "checkmark") {
                    guard !viewModel.brokerRequired else { return }
                    focusedField = nil
                    Task {
                        await viewModel.savePortfolio()
                        let symbols = viewModel.selectedStocks.map { $0.symbol }
                        onCompletion(symbols)
                    }
                }
                .disabled(viewModel.brokerRequired)
                .opacity(viewModel.brokerRequired ? 0.4 : 1)
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 12)
                .background(AppColor.background)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background(AppColor.background.edgesIgnoringSafeArea(.all))
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("完成") {
                    focusedField = nil
                }
                .font(.system(.body, design: .rounded))
                .fontWeight(.bold)
                .foregroundColor(AppColor.primary)
            }
        }
        .onAppear {
            Task { await viewModel.loadPopularStocks() }
        }
        .sheet(isPresented: $showScanSheet) {
            StockScanSimulatorView(
                onImport: { results, detectedBroker in
                    // 圖片匯入 → 券商變必選(辨識不一定準確),detectedBroker 只當建議
                    viewModel.importedFromScan = true
                    viewModel.detectedBroker = detectedBroker
                    for item in results {
                        viewModel.addScannedStock(item.stock, cost: item.cost, shares: item.shares)
                    }
                    showScanSheet = false
                },
                onMergeCompleted: {
                    // 9d 合併已直接寫入後端 → 關閉輸入頁讓列表刷新
                    showScanSheet = false
                    onCompletion([])
                }
            )
        }
        .sheet(isPresented: $showVoiceSheet) {
            VoiceHoldingsFlowView(
                onAddCompleted: { symbols in
                    // 19c「加入這 N 檔持股」已直接寫入後端 → 關閉輸入頁讓列表刷新
                    showVoiceSheet = false
                    onCompletion(symbols)
                },
                onManualSupplement: { drafts in
                    // 「有漏的?手動補上」:解析結果帶回手動輸入頁,結果保留
                    showVoiceSheet = false
                    for draft in drafts {
                        guard let symbol = draft.base.symbol else { continue }
                        let stock = Stock(symbol: symbol,
                                          name: draft.base.name ?? symbol,
                                          market: .tw,
                                          industry: nil)
                        viewModel.addScannedStock(stock, cost: draft.costText, shares: draft.sharesText)
                    }
                }
            )
            .interactiveDismissDisabled(false)
        }
        .alert("輸入券商名稱", isPresented: $showCustomBrokerInput) {
            TextField("例如 富邦證券", text: $customBrokerText)
            Button("確定") {
                let trimmed = customBrokerText.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty { viewModel.broker = trimmed }
            }
            Button("取消", role: .cancel) {}
        }
    }

    // MARK: - Scan entry

    private var scanEntryCard: some View {
        Button(action: {
            showScanSheet = true
        }) {
            HStack(spacing: 12) {
                Image(systemName: "camera.viewfinder")
                    .font(.title2)
                    .foregroundColor(AppColor.primary)

                VStack(alignment: .leading, spacing: 2) {
                    Text("拍照或匯入對帳單")
                        .font(.system(.subheadline, design: .rounded))
                        .fontWeight(.bold)
                        .foregroundColor(AppColor.textPrimary)
                    Text("上傳對帳單圖片，自動識別股票代號與成本")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundColor(AppColor.textSecondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.footnote)
                    .foregroundColor(AppColor.textSecondary)
            }
            .padding(14)
            .background(AppColor.cardBackground)
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(AppColor.primary.opacity(0.15), lineWidth: 1)
            )
            .shadow(color: Color(hex: "786446").opacity(0.04), radius: 8, x: 0, y: 4)
        }
    }

    // MARK: - Search box

    private var searchBox: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(AppColor.textSecondary)

            TextField("搜尋代號或名稱，例如 2330", text: $viewModel.searchText)
                .font(.system(.body, design: .rounded))
                .foregroundColor(AppColor.textPrimary)
                .focused($focusedField, equals: "search")

            if !viewModel.searchText.isEmpty {
                Button(action: { viewModel.searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(AppColor.textSecondary)
                }
            }
        }
        .padding(12)
        .background(AppColor.cardBackground)
        .cornerRadius(16)
        .shadow(color: Color(hex: "786446").opacity(0.04), radius: 8, x: 0, y: 4)
    }

    // MARK: - 券商選擇(手動選填、圖片匯入必填)

    private var brokerChip: some View {
        Menu {
            if let detected = viewModel.detectedBroker {
                Button("採用辨識結果:\(detected)") { viewModel.broker = detected }
                Divider()
            }
            ForEach(TaiwanBrokers.common, id: \.self) { name in
                Button(name) { viewModel.broker = name }
            }
            Button("其他券商…") {
                customBrokerText = viewModel.broker ?? viewModel.detectedBroker ?? ""
                showCustomBrokerInput = true
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "building.columns")
                    .font(.system(size: 14))
                    .foregroundColor(AppColor.primary)

                if let broker = viewModel.broker {
                    (Text("券商 ")
                        .foregroundColor(AppColor.textSecondary)
                     + Text(broker)
                        .fontWeight(.bold)
                        .foregroundColor(AppColor.textPrimary))
                        .font(.system(size: 12, design: .rounded))
                } else if viewModel.importedFromScan, let detected = viewModel.detectedBroker {
                    (Text("辨識為 ")
                        .foregroundColor(AppColor.amberStrong)
                     + Text(detected)
                        .fontWeight(.bold)
                        .foregroundColor(AppColor.amberStrong)
                     + Text(",請確認來源")
                        .foregroundColor(AppColor.amberStrong))
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                } else if viewModel.importedFromScan {
                    Text("辨識不出券商,請選擇來源")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(AppColor.amberStrong)
                } else {
                    Text("選擇券商(選填)")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(AppColor.textSecondary)
                }

                Spacer()

                Text(viewModel.broker == nil ? "選券商" : "更換")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(AppColor.primary)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(AppColor.cardBackground)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        viewModel.brokerRequired ? AppColor.amberBadge : Color(hex: "E3DFD4"),
                        lineWidth: viewModel.brokerRequired ? 1.5 : 1
                    )
            )
        }
    }

    // MARK: - Selected stocks + cost/shares editor

    private var selectedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("已選擇的持股 (\(viewModel.selectedStocks.count))")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(AppColor.textSecondary)

            brokerChip

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 90, maximum: 120))], alignment: .leading, spacing: 8) {
                ForEach(viewModel.selectedStocks) { stock in
                    HStack(spacing: 6) {
                        Text(stock.name)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundColor(AppColor.primary)
                            .lineLimit(1)

                        Button(action: {
                            viewModel.removeStock(stock)
                        }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(AppColor.primary)
                                .padding(3)
                                .background(AppColor.primary.opacity(0.1))
                                .clipShape(Circle())
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(AppColor.primary.opacity(0.08))
                    .cornerRadius(10)
                }
            }

            Text("設定持股成本與股數（選填）")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(AppColor.textSecondary)
                .padding(.top, 4)

            VStack(spacing: 10) {
                ForEach(viewModel.selectedStocks) { stock in
                    holdingEditorRow(stock)
                }
            }
        }
    }

    private func holdingEditorRow(_ stock: Stock) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(AppColor.primary.opacity(0.1))
                        .frame(width: 36, height: 36)
                    Text(String(stock.name.prefix(1)))
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(AppColor.primary)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(stock.name)
                        .font(.system(.subheadline, design: .rounded))
                        .fontWeight(.bold)
                        .foregroundColor(AppColor.textPrimary)
                    Text(stock.symbol)
                        .font(.system(.caption2, design: .rounded))
                        .foregroundColor(AppColor.textSecondary)
                }

                Spacer()
            }

            HStack(spacing: 10) {
                editorField(
                    label: "成本",
                    placeholder: "例如 980",
                    keyboard: .decimalPad,
                    focusKey: "cost-\(stock.symbol)",
                    text: Binding(
                        get: { viewModel.costPrices[stock.symbol] ?? "" },
                        set: { viewModel.costPrices[stock.symbol] = $0 }
                    )
                )

                editorField(
                    label: "股數",
                    placeholder: "例如 1000",
                    keyboard: .numberPad,
                    focusKey: "shares-\(stock.symbol)",
                    text: Binding(
                        get: { viewModel.shares[stock.symbol] ?? "" },
                        set: { viewModel.shares[stock.symbol] = $0 }
                    )
                )
            }
        }
        .padding(14)
        .background(AppColor.cardBackground)
        .cornerRadius(18)
        .shadow(color: Color(hex: "786446").opacity(0.05), radius: 8, x: 0, y: 4)
    }

    private func editorField(label: String, placeholder: String, keyboard: UIKeyboardType, focusKey: String, text: Binding<String>) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(AppColor.textSecondary)

            TextField(placeholder, text: text)
                .keyboardType(keyboard)
                .font(.system(.subheadline, design: .rounded).monospacedDigit())
                .foregroundColor(AppColor.textPrimary)
                .focused($focusedField, equals: focusKey)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(AppColor.background)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(
                    focusedField == focusKey ? AppColor.primary.opacity(0.6) : Color(hex: "E3DFD4"),
                    lineWidth: 1.2
                )
        )
        .frame(maxWidth: .infinity)
    }

    // MARK: - Search results / popular stocks

    @ViewBuilder
    private var resultsSection: some View {
        if viewModel.isLoading {
            HStack {
                Spacer()
                ProgressView()
                    .scaleEffect(1.2)
                    .padding(.vertical, 30)
                Spacer()
            }
        } else if viewModel.searchText.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("熱門搜尋股票")
                    .font(.system(.headline, design: .serif))
                    .foregroundColor(AppColor.textPrimary)

                VStack(spacing: 8) {
                    ForEach(viewModel.popularStocks) { stock in
                        stockRow(stock)
                    }
                }
            }
            .padding(.top, 8)
        } else if viewModel.searchResults.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 40))
                    .foregroundColor(AppColor.textSecondary.opacity(0.5))
                Text("找不到相符的股票")
                    .font(.system(.headline, design: .rounded))
                    .foregroundColor(AppColor.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
        } else {
            VStack(spacing: 8) {
                ForEach(viewModel.searchResults) { stock in
                    stockRow(stock)
                }
            }
            .padding(.top, 8)
        }
    }

    private func stockRow(_ stock: Stock) -> some View {
        Button(action: {
            viewModel.selectStock(stock)
        }) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(stock.name)
                        .font(.system(.body, design: .rounded))
                        .fontWeight(.semibold)
                        .foregroundColor(AppColor.textPrimary)
                    Text(stock.symbol)
                        .font(.system(.caption, design: .rounded))
                        .foregroundColor(AppColor.textSecondary)
                }
                Spacer()

                // Toggle icon state: show checkmark if selected, plus if not
                let isSelected = viewModel.selectedStocks.contains(where: { $0.symbol == stock.symbol })
                Image(systemName: isSelected ? "checkmark.circle.fill" : "plus.circle.fill")
                    .foregroundColor(isSelected ? Color(hex: "6E9A7F") : AppColor.primary)
                    .font(.title3)
                    .scaleEffect(isSelected ? 1.1 : 1.0)
                    .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isSelected)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(AppColor.cardBackground)
            .cornerRadius(14)
            .shadow(color: Color(hex: "786446").opacity(0.03), radius: 6, x: 0, y: 3)
        }
    }
}
