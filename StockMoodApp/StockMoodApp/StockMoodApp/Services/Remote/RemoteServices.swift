import Foundation

// MARK: - API Request Bodies
struct PortfolioItemCreateBody: Codable {
    let symbol: String
    let costPrice: Double?
    let shares: Int?
}

struct ReminderSettingBody: Codable {
    let enabled: Bool
    let timeSlot: String
    let items: ReminderItemsBody
}

struct ReminderItemsBody: Codable {
    let anxietyScore: Bool
    let dailyCard: Bool
    let volatilityAlert: Bool
}

// MARK: - Remote Portfolio Service
class RemotePortfolioService: PortfolioServiceProtocol {
    func getPortfolioItems() async throws -> [PortfolioItem] {
        return try await APIClient.shared.request("/portfolio/items", method: "GET")
    }
    
    func addPortfolioItem(_ item: PortfolioItem) async throws {
        let bodyObj = PortfolioItemCreateBody(
            symbol: item.symbol,
            costPrice: item.costPrice,
            shares: item.shares
        )
        
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let bodyData = try encoder.encode(bodyObj)
        
        let _: PortfolioItem = try await APIClient.shared.request("/portfolio/items", method: "POST", body: bodyData)
    }
    
    func deletePortfolioItem(id: UUID) async throws {
        let _: Bool = try await APIClient.shared.request("/portfolio/items/\(id.uuidString.lowercased())", method: "DELETE")
    }
}

// MARK: - Remote Holding Service(持股異動與多券商合併 · spec 04)
class RemoteHoldingService: HoldingServiceProtocol {
    func getHoldings() async throws -> [Holding] {
        return try await APIClient.shared.request("/portfolio/holdings", method: "GET")
    }

    func getHolding(symbol: String) async throws -> Holding? {
        do {
            let holding: Holding = try await APIClient.shared.request("/portfolio/holdings/\(symbol)", method: "GET")
            return holding
        } catch APIError.invalidResponse {
            // 404 = 尚未持有這檔 → 以 nil 表示,不是錯誤
            return nil
        }
    }

    func buy(symbol: String, shares: Int, price: Double?, broker: String?) async throws -> TradeResult {
        return try await APIClient.shared.requestBody(
            "/portfolio/holdings/\(symbol)/buy",
            body: TradeRequestBody(shares: shares, price: price, broker: broker)
        )
    }

    func sell(symbol: String, shares: Int, price: Double?, broker: String?) async throws -> TradeResult {
        return try await APIClient.shared.requestBody(
            "/portfolio/holdings/\(symbol)/sell",
            body: TradeRequestBody(shares: shares, price: price, broker: broker)
        )
    }

    func override(symbol: String, shares: Int, broker: String?) async throws -> TradeResult {
        return try await APIClient.shared.requestBody(
            "/portfolio/holdings/\(symbol)/override",
            body: OverrideRequestBody(shares: shares, broker: broker)
        )
    }

    func restore(symbol: String) async throws -> TradeResult {
        return try await APIClient.shared.request("/portfolio/holdings/\(symbol)/restore", method: "POST")
    }

    func importMerge(decisions: [MergeDecision]) async throws -> ImportMergeResult {
        return try await APIClient.shared.requestBody(
            "/portfolio/import/merge",
            body: ImportMergeRequestBody(decisions: decisions)
        )
    }

    func getActivities(symbol: String) async throws -> [HoldingActivity] {
        return try await APIClient.shared.request("/portfolio/holdings/\(symbol)/activities", method: "GET")
    }

    func deleteActivity(id: String) async throws {
        let _: Bool = try await APIClient.shared.request("/portfolio/activities/\(id)", method: "DELETE")
    }

    func deleteLot(id: String) async throws {
        // 分帳就是一筆 PortfolioItem,沿用既有刪除端點
        let _: Bool = try await APIClient.shared.request("/portfolio/items/\(id)", method: "DELETE")
    }
}

// MARK: - Remote Stock Service
class RemoteStockService: StockServiceProtocol {
    func searchStocks(keyword: String) async throws -> [Stock] {
        let encodedKeyword = keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return try await APIClient.shared.request("/stocks/search?keyword=\(encodedKeyword)", method: "GET")
    }
    
    func getDailyPrice(symbol: String) async throws -> StockDailyPrice {
        return try await APIClient.shared.request("/stocks/\(symbol)/daily", method: "GET")
    }
    
    func getRecommendations(symbol: String) async throws -> [Stock] {
        return try await APIClient.shared.request("/recommendations/stocks?symbol=\(symbol)", method: "GET")
    }
}

// MARK: - Remote Anxiety Service
class RemoteAnxietyService: AnxietyServiceProtocol {
    func getTodayAnxiety() async throws -> AnxietyResult {
        return try await APIClient.shared.request("/anxiety/today", method: "GET")
    }
}

// MARK: - Remote Daily Summary Service
class RemoteDailySummaryService: DailySummaryServiceProtocol {
    func getDailySummary() async throws -> DailySummary {
        return try await APIClient.shared.request("/daily-summary", method: "GET")
    }
}

// MARK: - Remote Card Draw Service
class RemoteCardDrawService: CardDrawServiceProtocol {
    func drawTodayCard() async throws -> DrawCardResult {
        return try await APIClient.shared.request("/cards/draw", method: "POST")
    }
    
    func getTodayCard() async throws -> DrawCardResult? {
        return try await APIClient.shared.request("/cards/today", method: "GET")
    }
}

// MARK: - Remote Market Service
class RemoteMarketService: MarketServiceProtocol {
    func getMarketCompare() async throws -> MarketCompareResult {
        return try await APIClient.shared.request("/market/compare", method: "GET")
    }
}

// MARK: - Remote Analysis Service(庫存分析 + 個股 AI 觀點)
class RemoteAnalysisService: AnalysisServiceProtocol {
    func getPortfolioAnalysis() async throws -> PortfolioAnalysis {
        return try await APIClient.shared.request("/portfolio/analysis", method: "GET")
    }

    func getInsights() async throws -> InsightList {
        return try await APIClient.shared.request("/insights", method: "GET")
    }

    func getInsightDetail(symbol: String) async throws -> StockInsightDetail {
        let encoded = symbol.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? symbol
        return try await APIClient.shared.request("/insights/\(encoded)", method: "GET")
    }
}

// MARK: - Remote Reminder Service
class RemoteReminderService: ReminderServiceProtocol {
    func getReminderSetting() async throws -> ReminderSetting {
        let rawSetting: ReminderSetting = try await APIClient.shared.request("/reminder-setting", method: "GET")
        return rawSetting
    }
    
    func saveReminderSetting(_ setting: ReminderSetting) async throws {
        let bodyObj = ReminderSettingBody(
            enabled: setting.enabled,
            timeSlot: setting.timeSlot.rawValue,
            items: ReminderItemsBody(
                anxietyScore: setting.items.anxietyScore,
                dailyCard: setting.items.dailyCard,
                volatilityAlert: setting.items.volatilityAlert
            )
        )
        
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let bodyData = try encoder.encode(bodyObj)
        
        let _: ReminderSetting = try await APIClient.shared.request("/reminder-setting", method: "PUT", body: bodyData)
    }
}
