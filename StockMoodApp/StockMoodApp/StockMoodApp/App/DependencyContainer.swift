import Foundation
import Combine

class DependencyContainer: ObservableObject {
    static let shared = DependencyContainer()

    // Live backend services only — mock mode was removed so the app always
    // reflects real data from the API
    let portfolioService: PortfolioServiceProtocol = RemotePortfolioService()
    let holdingService: HoldingServiceProtocol = RemoteHoldingService()
    let privacyService: PrivacyServiceProtocol = RemotePrivacyService()
    let stockService: StockServiceProtocol = RemoteStockService()
    let anxietyService: AnxietyServiceProtocol = RemoteAnxietyService()
    let dailySummaryService: DailySummaryServiceProtocol = RemoteDailySummaryService()
    let cardDrawService: CardDrawServiceProtocol = RemoteCardDrawService()
    let marketService: MarketServiceProtocol = RemoteMarketService()
    let reminderService: ReminderServiceProtocol = RemoteReminderService()
    let analysisService: AnalysisServiceProtocol = RemoteAnalysisService()

    private init() {}
}
