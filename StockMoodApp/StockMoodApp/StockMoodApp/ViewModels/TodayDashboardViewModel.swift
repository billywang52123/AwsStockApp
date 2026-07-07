import Foundation
import SwiftUI
import Combine

@MainActor
class TodayDashboardViewModel: ObservableObject {
    @Published var anxietyScore = 30
    @Published var anxietyLevel = "穩定"
    @Published var mainReason = ""
    @Published var anxietyMessage = ""
    @Published var compareResult: MarketCompareResult? = nil
    
    @Published var isLoading = false
    @Published var hasPortfolioItems = false
    @Published var hasError = false
    @Published var errorMessage = ""
    
    private let container: DependencyContainer
    
    init(container: DependencyContainer? = nil) {
        self.container = container ?? .shared
    }
    
    func loadData() async {
        isLoading = true
        hasError = false
        do {
            let items = try await container.portfolioService.getPortfolioItems()
            hasPortfolioItems = !items.isEmpty
            
            if hasPortfolioItems {
                let anxiety = try await container.anxietyService.getTodayAnxiety()
                self.anxietyScore = anxiety.score
                self.anxietyLevel = anxiety.level
                self.mainReason = anxiety.mainReason
                self.anxietyMessage = anxiety.message
                
                let market = try await container.marketService.getMarketCompare()
                self.compareResult = market
            }
        } catch {
            hasError = true
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
