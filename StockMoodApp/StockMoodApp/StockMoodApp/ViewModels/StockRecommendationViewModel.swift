import Foundation
import SwiftUI
import Combine

@MainActor
class StockRecommendationViewModel: ObservableObject {
    @Published var recommendations: [RecommendedStock] = []
    @Published var isLoading = false
    @Published var hasError = false
    @Published var errorMessage = ""
    
    private let container: DependencyContainer
    
    init(container: DependencyContainer? = nil) {
        self.container = container ?? .shared
    }
    
    func loadRecommendations(for symbols: [String]) async {
        isLoading = true
        hasError = false
        recommendations = []
        
        let targetSymbol = symbols.first ?? "2330" // Fallback to TSMC
        do {
            recommendations = try await container.stockService.getRecommendations(symbol: targetSymbol)
        } catch {
            hasError = true
            errorMessage = error.localizedDescription
            print("Failed load recommendations: \(error)")
        }
        isLoading = false
    }
    
    func addRecommendation(_ stock: RecommendedStock) async {
        let item = PortfolioItem(id: UUID(), symbol: stock.symbol, name: stock.name, costPrice: nil, shares: nil, createdAt: Date())
        hasError = false
        do {
            try await container.portfolioService.addPortfolioItem(item)
            recommendations.removeAll(where: { $0.symbol == stock.symbol })
            HapticManager.shared.triggerNotification(type: .success)
        } catch {
            hasError = true
            errorMessage = error.localizedDescription
            print("Failed to add recommended item: \(error)")
        }
    }
}
