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
            for holding in holdings {
                let price = try await container.stockService.getDailyPrice(symbol: holding.symbol)
                dailyPrices[holding.symbol] = price
            }
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
