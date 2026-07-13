import Foundation
import SwiftUI
import Combine

@MainActor
class PortfolioInputViewModel: ObservableObject {
    @Published var searchText = ""
    @Published var searchResults: [Stock] = []
    @Published var popularStocks: [Stock] = []
    @Published var selectedStocks: [Stock] = []
    @Published var costPrices: [String: String] = [:]
    @Published var shares: [String: String] = [:]
    /// 這批持股所屬券商(手動可選填、圖片匯入時必填);nil = 未選
    @Published var broker: String?
    /// 影像辨識推測的券商,只當建議(不一定準確),不自動採用
    @Published var detectedBroker: String?
    /// 這批持股是否來自圖片匯入 → 券商變必選(辨識不可靠,一律要用戶確認)
    @Published var importedFromScan = false
    @Published var isLoading = false
    @Published var hasError = false
    @Published var errorMessage = ""

    /// 圖片匯入一律要求先選定券商;純手動新增則為選填
    var brokerRequired: Bool { importedFromScan && broker == nil }
    
    private let container: DependencyContainer
    private var cancellables = Set<AnyCancellable>()
    
    init(container: DependencyContainer? = nil) {
        self.container = container ?? .shared
        
        $searchText
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .removeDuplicates()
            .sink { [weak self] keyword in
                guard let self = self else { return }
                Task {
                    await self.performSearch(keyword: keyword)
                }
            }
            .store(in: &cancellables)
    }
    
    /// Loads the quick-start list from the backend (empty keyword returns all stocks).
    func loadPopularStocks() async {
        guard popularStocks.isEmpty else { return }
        do {
            let all = try await container.stockService.searchStocks(keyword: "")
            popularStocks = Array(all.prefix(5))
        } catch {
            print("Load popular stocks failed: \(error)")
        }
    }

    func performSearch(keyword: String) async {
        guard !keyword.isEmpty else {
            self.searchResults = []
            return
        }
        isLoading = true
        hasError = false
        do {
            searchResults = try await container.stockService.searchStocks(keyword: keyword)
        } catch {
            hasError = true
            errorMessage = error.localizedDescription
            print("Search failed: \(error)")
        }
        isLoading = false
    }
    
    func selectStock(_ stock: Stock) {
        if selectedStocks.contains(where: { $0.symbol == stock.symbol }) {
            removeStock(stock)
            return
        }
        
        guard selectedStocks.count < 5 else {
            HapticManager.shared.triggerNotification(type: .error)
            return
        }
        
        selectedStocks.append(stock)

        // Cost / shares are optional — leave them blank for the user to fill in
        costPrices[stock.symbol] = ""
        shares[stock.symbol] = ""

        HapticManager.shared.triggerSelection()
    }
    
    func addScannedStock(_ stock: Stock, cost: String, shares: String) {
        if selectedStocks.contains(where: { $0.symbol == stock.symbol }) {
            costPrices[stock.symbol] = cost
            self.shares[stock.symbol] = shares
            return
        }
        
        guard selectedStocks.count < 5 else {
            HapticManager.shared.triggerNotification(type: .error)
            return
        }
        
        selectedStocks.append(stock)
        costPrices[stock.symbol] = cost
        self.shares[stock.symbol] = shares
        HapticManager.shared.triggerSelection()
    }
    
    func removeStock(_ stock: Stock) {
        selectedStocks.removeAll(where: { $0.symbol == stock.symbol })
        costPrices.removeValue(forKey: stock.symbol)
        shares.removeValue(forKey: stock.symbol)
        HapticManager.shared.triggerSelection()
    }
    
    func savePortfolio() async {
        isLoading = true
        hasError = false
        for stock in selectedStocks {
            let costVal = Double(costPrices[stock.symbol] ?? "")
            let sharesVal = Int(shares[stock.symbol] ?? "")
            
            let item = PortfolioItem(
                id: UUID(),
                symbol: stock.symbol,
                name: stock.name,
                costPrice: costVal,
                shares: sharesVal,
                broker: broker,
                createdAt: Date()
            )
            do {
                try await container.portfolioService.addPortfolioItem(item)
            } catch {
                hasError = true
                errorMessage = error.localizedDescription
                print("Save portfolio item failed: \(error)")
            }
        }
        isLoading = false
        if !hasError {
            HapticManager.shared.triggerNotification(type: .success)
            // New holdings can unlock achievements (手動派、題材、組合…)
            AchievementCenter.shared.evaluate()
        }
    }
}
