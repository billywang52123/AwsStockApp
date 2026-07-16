import Foundation
import SwiftUI
import Combine

@MainActor
class PortfolioListViewModel: ObservableObject {
    /// 聚合後的持股:多券商分帳加總、加權均價(spec 04)
    @Published var holdings: [Holding] = []
    @Published var dailyPrices: [String: StockDailyPrice] = [:]
    @Published var isLoading = false
    @Published var hasError = false
    @Published var errorMessage = ""

    private let container: DependencyContainer

    init(container: DependencyContainer? = nil) {
        self.container = container ?? .shared
    }

    func loadPortfolio() async {
        isLoading = holdings.isEmpty
        hasError = false
        do {
            holdings = try await container.holdingService.getHoldings()
            // 各檔股價並行抓:原本逐檔序列等待,N 檔就是 N 趟往返,持股頁會轉圈很久
            let stockService = container.stockService
            let prices = try await withThrowingTaskGroup(
                of: (String, StockDailyPrice).self
            ) { group in
                for holding in holdings {
                    let symbol = holding.symbol
                    group.addTask {
                        (symbol, try await stockService.getDailyPrice(symbol: symbol))
                    }
                }
                var result: [String: StockDailyPrice] = [:]
                for try await (symbol, price) in group {
                    result[symbol] = price
                }
                return result
            }
            dailyPrices = prices
        } catch {
            hasError = true
            errorMessage = error.localizedDescription
            print("Load portfolio list failed: \(error)")
        }
        isLoading = false
    }

    /// 刪除整檔持股 = 刪掉它所有券商分帳
    func deleteHolding(_ holding: Holding) async {
        HapticManager.shared.triggerImpact(style: .light)
        hasError = false
        do {
            for lot in holding.lots {
                try await container.holdingService.deleteLot(id: lot.id)
            }
            holdings.removeAll(where: { $0.symbol == holding.symbol })
        } catch {
            hasError = true
            errorMessage = error.localizedDescription
            print("Delete failed: \(error)")
        }
    }
}
