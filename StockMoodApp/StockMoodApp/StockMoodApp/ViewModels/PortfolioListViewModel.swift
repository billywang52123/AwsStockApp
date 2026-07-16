import Foundation
import SwiftUI
import Combine

@MainActor
class PortfolioListViewModel: ObservableObject {
    /// App 全域共用一份:啟動時 AppTabView 就先 loadPortfolio(),
    /// 使用者點進「持股」分頁時資料已在記憶體,零等待。
    static let shared = PortfolioListViewModel()

    /// 聚合後的持股:多券商分帳加總、加權均價(spec 04)
    @Published var holdings: [Holding] = []
    @Published var dailyPrices: [String: StockDailyPrice] = [:]
    @Published var isLoading = false
    @Published var hasError = false
    @Published var errorMessage = ""

    private let container: DependencyContainer
    private var cancellables = Set<AnyCancellable>()

    init(container: DependencyContainer? = nil) {
        self.container = container ?? .shared
        // 模擬日期切換後股價/漲跌都是另一天的,自動重載,不必等使用者進分頁下拉
        NotificationCenter.default.publisher(for: .simDateDidChange)
            .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { await self?.loadPortfolio() }
            }
            .store(in: &cancellables)
    }

    private var loadInFlight = false

    /// 登出時清空共用資料,下一位登入者不會看到上一位的持股
    func reset() {
        holdings = []
        dailyPrices = [:]
        hasError = false
        errorMessage = ""
    }

    func loadPortfolio() async {
        // 啟動預載與分頁 onAppear 可能同時觸發;已在載入中就不重打
        if loadInFlight { return }
        loadInFlight = true
        defer { loadInFlight = false }
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
