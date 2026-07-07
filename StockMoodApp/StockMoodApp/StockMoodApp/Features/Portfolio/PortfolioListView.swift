import SwiftUI

struct PortfolioListView: View {
    @StateObject private var viewModel = PortfolioListViewModel()
    @State private var showInputSheet = false
    
    var body: some View {
        NavigationView {
            ZStack {
                AppColor.background
                    .edgesIgnoringSafeArea(.all)
                
                if viewModel.isLoading {
                    ProgressView("正在取得持股資訊...")
                } else if viewModel.portfolioItems.isEmpty {
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
                            Section(header: Text("我的持股清單 (\(viewModel.portfolioItems.count))")
                                .font(.system(.footnote, design: .rounded))
                                .foregroundColor(AppColor.textSecondary)
                            ) {
                                ForEach(viewModel.portfolioItems) { item in
                                    let priceInfo = viewModel.dailyPrices[item.symbol]
                                    let change = priceInfo?.changePercent ?? 0.0
                                    let isUp = change >= 0
                                    
                                    // Calculate Profit & Loss (P&L)
                                    let hasPosition = item.shares != nil && item.costPrice != nil
                                    let shares = Double(item.shares ?? 0)
                                    let cost = item.costPrice ?? 0.0
                                    let currentPrice = priceInfo?.closePrice ?? cost
                                    let pnl = hasPosition ? ((currentPrice - cost) * shares) : 0.0
                                    let pnlPercent = (hasPosition && cost > 0) ? ((currentPrice - cost) / cost * 100.0) : 0.0
                                    let isPnlUp = pnl >= 0
                                    
                                    NavigationLink(destination: StockDetailView(symbol: item.symbol, name: item.name)) {
                                        HStack(spacing: 16) {
                                            // Symbol, Name & Position Details
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(item.name)
                                                    .font(.system(.body, design: .rounded))
                                                    .fontWeight(.bold)
                                                    .foregroundColor(AppColor.textPrimary)
                                                
                                                HStack(spacing: 6) {
                                                    Text(item.symbol)
                                                        .font(.system(.caption, design: .rounded))
                                                        .foregroundColor(AppColor.textSecondary)
                                                    
                                                    if hasPosition {
                                                        Text("•")
                                                            .font(.system(.caption2))
                                                            .foregroundColor(AppColor.textSecondary.opacity(0.5))
                                                        Text("\(item.shares ?? 0)股 @ $\(String(format: "%.1f", cost))")
                                                            .font(.system(.caption, design: .rounded))
                                                            .foregroundColor(AppColor.textSecondary)
                                                    }
                                                }
                                            }
                                            
                                            Spacer()
                                            
                                            // Current Price & P&L Info
                                            VStack(alignment: .trailing, spacing: 4) {
                                                if let price = priceInfo {
                                                    // Current Close Price
                                                    Text(String(format: "$%.2f", price.closePrice))
                                                        .font(.system(.subheadline, design: .rounded))
                                                        .fontWeight(.bold)
                                                        .foregroundColor(AppColor.textPrimary)
                                                    
                                                    // Total position P&L or daily stock change
                                                    if hasPosition {
                                                        let pnlSign = isPnlUp ? "+" : ""
                                                        Text(String(format: "損益: %@$%.0f (%@%.2f%%)", pnlSign, pnl, pnlSign, pnlPercent))
                                                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                                                            .foregroundColor(isPnlUp ? AppColor.upText : AppColor.downText)
                                                    } else {
                                                        Text(String(format: "%@%.2f%%", isUp ? "+" : "", change))
                                                            .font(.system(.caption, design: .rounded))
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
                    Button(action: { showInputSheet = true }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .foregroundColor(AppColor.primary)
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
    
    private func deleteItems(at offsets: IndexSet) {
        for index in offsets {
            let item = viewModel.portfolioItems[index]
            Task {
                await viewModel.deleteItem(id: item.id)
            }
        }
    }
}
