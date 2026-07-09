import Foundation

protocol PortfolioServiceProtocol {
    func getPortfolioItems() async throws -> [PortfolioItem]
    func addPortfolioItem(_ item: PortfolioItem) async throws
    func deletePortfolioItem(id: UUID) async throws
}

/// 持股異動與多券商合併(spec 04 · 9a–9e)
protocol HoldingServiceProtocol {
    func getHoldings() async throws -> [Holding]
    func getHolding(symbol: String) async throws -> Holding?
    func buy(symbol: String, shares: Int, price: Double?, broker: String?) async throws -> TradeResult
    func sell(symbol: String, shares: Int, price: Double?, broker: String?) async throws -> TradeResult
    func override(symbol: String, shares: Int, broker: String?) async throws -> TradeResult
    func restore(symbol: String) async throws -> TradeResult
    func importMerge(decisions: [MergeDecision]) async throws -> ImportMergeResult
    func getActivities(symbol: String) async throws -> [HoldingActivity]
    func deleteActivity(id: String) async throws
    func deleteLot(id: String) async throws
}

/// 隱私儀表板(spec 05 · 10a)
protocol PrivacyServiceProtocol {
    func getSummary() async throws -> PrivacySummary
    func deleteAllData() async throws -> PrivacySummary
}

protocol StockServiceProtocol {
    func searchStocks(keyword: String) async throws -> [Stock]
    func getDailyPrice(symbol: String) async throws -> StockDailyPrice
    func getRecommendations(symbol: String) async throws -> [RecommendedStock]
}

/// 觀察清單(spec 05 · 11a–11g)
protocol WatchlistServiceProtocol {
    func getIndex() async throws -> WatchlistIndex
    func createWatchlist(name: String, color: String?) async throws -> WatchlistSummary
    func deleteWatchlist(id: String) async throws
    func getDetail(id: String) async throws -> WatchlistDetail
    func addItem(watchlistId: String, symbol: String) async throws -> WatchStock
    func removeItem(watchlistId: String, symbol: String) async throws
    func convertToHolding(watchlistId: String, symbol: String, shares: Int, price: Double?) async throws -> ConvertResult
    func getAnalysis(watchlistId: String?) async throws -> WatchlistAnalysis
    func getWatchInsights() async throws -> WatchInsightList
}

protocol AnxietyServiceProtocol {
    func getTodayAnxiety() async throws -> AnxietyResult
}

protocol DailySummaryServiceProtocol {
    func getDailySummary() async throws -> DailySummary
}

/// 每日御神籤(spec 第十輪 12a–12d,取代原每日抽卡)
protocol FortuneServiceProtocol {
    func drawFortune() async throws -> FortuneResult
    func getTodayFortune() async throws -> FortuneResult?
}

protocol MarketServiceProtocol {
    func getMarketCompare() async throws -> MarketCompareResult
}

protocol AnalysisServiceProtocol {
    func getPortfolioAnalysis() async throws -> PortfolioAnalysis
    func getInsights() async throws -> InsightList
    func getInsightDetail(symbol: String) async throws -> StockInsightDetail
}

protocol ReminderServiceProtocol {
    func getReminderSetting() async throws -> ReminderSetting
    func saveReminderSetting(_ setting: ReminderSetting) async throws
}
