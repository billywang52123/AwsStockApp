import Foundation

protocol PortfolioServiceProtocol {
    func getPortfolioItems() async throws -> [PortfolioItem]
    func addPortfolioItem(_ item: PortfolioItem) async throws
    func deletePortfolioItem(id: UUID) async throws
}

protocol StockServiceProtocol {
    func searchStocks(keyword: String) async throws -> [Stock]
    func getDailyPrice(symbol: String) async throws -> StockDailyPrice
    func getRecommendations(symbol: String) async throws -> [Stock]
}

protocol AnxietyServiceProtocol {
    func getTodayAnxiety() async throws -> AnxietyResult
}

protocol DailySummaryServiceProtocol {
    func getDailySummary() async throws -> DailySummary
}

protocol CardDrawServiceProtocol {
    func drawTodayCard() async throws -> DrawCardResult
    func getTodayCard() async throws -> DrawCardResult?
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
