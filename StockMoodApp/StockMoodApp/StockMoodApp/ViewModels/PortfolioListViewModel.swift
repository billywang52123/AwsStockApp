import Foundation
import SwiftUI
import Combine

@MainActor
class PortfolioListViewModel: ObservableObject {
    @Published var portfolioItems: [PortfolioItem] = []
    @Published var dailyPrices: [String: StockDailyPrice] = [:]
    @Published var isLoading = false
    @Published var hasError = false
    @Published var errorMessage = ""
    
    private let container: DependencyContainer
    
    init(container: DependencyContainer? = nil) {
        self.container = container ?? .shared
    }
    
    func loadPortfolio() async {
        isLoading = true
        hasError = false
        do {
            portfolioItems = try await container.portfolioService.getPortfolioItems()
            for item in portfolioItems {
                let price = try await container.stockService.getDailyPrice(symbol: item.symbol)
                dailyPrices[item.symbol] = price
            }
        } catch {
            hasError = true
            errorMessage = error.localizedDescription
            print("Load portfolio list failed: \(error)")
        }
        isLoading = false
    }
    
    func deleteItem(id: UUID) async {
        HapticManager.shared.triggerImpact(style: .light)
        hasError = false
        do {
            try await container.portfolioService.deletePortfolioItem(id: id)
            portfolioItems.removeAll(where: { $0.id == id })
        } catch {
            hasError = true
            errorMessage = error.localizedDescription
            print("Delete failed: \(error)")
        }
    }
}
