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
    private var cancellables = Set<AnyCancellable>()

    init(container: DependencyContainer? = nil) {
        self.container = container ?? .shared
        // 持股異動、模擬日期切換後焦慮分數/大盤比較也要跟著變,自動重載
        NotificationCenter.default.publisher(for: .holdingsDidChange)
            .merge(with: NotificationCenter.default.publisher(for: .simDateDidChange))
            .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { await self?.loadData() }
            }
            .store(in: &cancellables)
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
