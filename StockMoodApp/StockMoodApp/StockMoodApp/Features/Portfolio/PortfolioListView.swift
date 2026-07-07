import SwiftUI

struct PortfolioListView: View {
    @StateObject private var viewModel = PortfolioListViewModel()
    @ObservedObject private var privacy = PrivacyManager.shared
    @State private var showInputSheet = false

    var body: some View {
        NavigationView {
            ZStack {
                AppColor.background
                    .edgesIgnoringSafeArea(.all)

                if privacy.faceIDLockEnabled && !privacy.holdingsUnlocked {
                    // 10c Face ID 鎖:未解鎖前整頁遮罩
                    HoldingsLockView()
                } else if viewModel.isLoading {
                    ProgressView("正在取得持股資訊...")
                } else if viewModel.holdings.isEmpty {
                    EmptyStateView(
                        title: "尚未加入任何持股",
                        message: "添加您的第 1 檔持股，我們將為您呈現今日股價波動以及情緒陪伴分析。",
                        buttonTitle: "新增持股"
                    ) {
                        showInputSheet = true
                    }
                } else {
                    VStack(alignment: .leading) {
                        List {
                            Section(header: Text("我的持股清單 (\(viewModel.holdings.count))")
                                .font(.system(.footnote, design: .rounded))
                                .foregroundColor(AppColor.textSecondary)
                            ) {
                                ForEach(viewModel.holdings) { holding in
                                    holdingRow(holding)
                                }
                                .onDelete(perform: deleteItems)
                            }
                        }
                        .listStyle(InsetGroupedListStyle())
                        .scrollContentBackground(.hidden)
                        
                        DisclaimerView()
                            .frame(maxWidth: .infinity)
                            .padding(.bottom, 16)
                    }
                }
            }
            .navigationTitle("持股管理")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 0) {
                        // 10c 金額模糊眼睛鈕(全 App 同步)
                        AmountBlurToggle()

                        Button(action: { showInputSheet = true }) {
                            Image(systemName: "plus.circle.fill")
                                .font(.title3)
                                .foregroundColor(AppColor.primary)
                        }
                    }
                }
            }
            .sheet(isPresented: $showInputSheet, onDismiss: {
                Task {
                    await viewModel.loadPortfolio()
                }
            }) {
                PortfolioInputView { _ in
                    showInputSheet = false
                }
            }
            .onAppear {
                Task {
                    await viewModel.loadPortfolio()
                }
            }
        }
    }
    
    // MARK: - 持股列(聚合:多券商分帳加總 + 加權均價)

    private func holdingRow(_ holding: Holding) -> some View {
        let priceInfo = viewModel.dailyPrices[holding.symbol]
        let change = priceInfo?.changePercent ?? 0.0
        let isUp = change >= 0

        let hasPosition = holding.totalShares > 0 && holding.avgPrice != nil
        let shares = Double(holding.totalShares)
        let cost = holding.avgPrice ?? 0.0
        let currentPrice = priceInfo?.closePrice ?? cost
        let pnl = hasPosition ? ((currentPrice - cost) * shares) : 0.0
        let pnlPercent = (hasPosition && cost > 0) ? ((currentPrice - cost) / cost * 100.0) : 0.0
        let isPnlUp = pnl >= 0

        return NavigationLink(destination: StockDetailView(symbol: holding.symbol, name: holding.name)) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(holding.name)
                            .font(.system(.body, design: .rounded))
                            .fontWeight(.bold)
                            .foregroundColor(AppColor.textPrimary)

                        if holding.lots.count > 1 {
                            Text("\(holding.lots.count) 券商")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundColor(AppColor.primary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color(hex: "EEEEFA"))
                                .clipShape(Capsule())
                        }
                    }

                    HStack(spacing: 6) {
                        Text(holding.symbol)
                            .font(.system(.caption, design: .rounded))
                            .foregroundColor(AppColor.textSecondary)

                        if holding.totalShares > 0 {
                            Text("•")
                                .font(.system(.caption2))
                                .foregroundColor(AppColor.textSecondary.opacity(0.5))
                            Text(holdingPositionText(holding))
                                .font(.system(.caption, design: .rounded).monospacedDigit())
                                .foregroundColor(AppColor.textSecondary)
                                .sensitiveAmount()
                        }
                    }

                    if holding.avgPriceIncomplete {
                        Text("有分帳未填買價")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundColor(AppColor.amberStrong)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    if let price = priceInfo {
                        Text(String(format: "$%.2f", price.closePrice))
                            .font(.system(.subheadline, design: .rounded).monospacedDigit())
                            .fontWeight(.bold)
                            .foregroundColor(AppColor.textPrimary)

                        if hasPosition {
                            let pnlSign = isPnlUp ? "+" : ""
                            Text(String(format: "損益: %@$%.0f (%@%.2f%%)", pnlSign, pnl, pnlSign, pnlPercent))
                                .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
                                .foregroundColor(isPnlUp ? AppColor.upText : AppColor.downText)
                                .sensitiveAmount()
                        } else {
                            Text(String(format: "%@%.2f%%", isUp ? "+" : "", change))
                                .font(.system(.caption, design: .rounded).monospacedDigit())
                                .fontWeight(.semibold)
                                .foregroundColor(isUp ? AppColor.upText : AppColor.downText)
                        }
                    } else {
                        Text("--")
                            .foregroundColor(AppColor.textSecondary)
                    }
                }
            }
            .padding(.vertical, 6)
        }
    }

    private func holdingPositionText(_ holding: Holding) -> String {
        var text = "\(holding.totalShares.formatted())股"
        if let avg = holding.avgPrice {
            text += " @ $\(avg.trimmedString)"
        }
        return text
    }

    private func deleteItems(at offsets: IndexSet) {
        for index in offsets {
            let holding = viewModel.holdings[index]
            Task {
                await viewModel.deleteHolding(holding)
            }
        }
    }
}
