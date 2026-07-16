import Foundation

// MARK: - API Request Bodies
struct PortfolioItemCreateBody: Codable {
    let symbol: String
    let costPrice: Double?
    let shares: Int?
    let broker: String?
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

/// 資料異動成功後統一從服務層廣播,任何入口(持股頁、詳情頁、匯入、觀察清單)改動都會通知到監聽頁面。
private func postDataChanged(_ name: Notification.Name) {
    NotificationCenter.default.post(name: name, object: nil)
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
            shares: item.shares,
            broker: item.broker
        )
        
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let bodyData = try encoder.encode(bodyObj)
        
        let _: PortfolioItem = try await APIClient.shared.request("/portfolio/items", method: "POST", body: bodyData)
        postDataChanged(.holdingsDidChange)
    }

    func deletePortfolioItem(id: UUID) async throws {
        let _: Bool = try await APIClient.shared.request("/portfolio/items/\(id.uuidString.lowercased())", method: "DELETE")
        postDataChanged(.holdingsDidChange)
    }

    func parseVoiceHoldings(text: String) async throws -> VoiceParseResult {
        // 只傳裝置端轉好的純文字逐字稿,錄音檔不上傳(spec 08)
        return try await APIClient.shared.requestBody(
            "/portfolio/holdings/parse-voice",
            body: VoiceParseRequestBody(text: text)
        )
    }
}

private struct VoiceParseRequestBody: Encodable {
    let text: String
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
        } catch APIError.invalidResponse(_, 404) {
            // 404 = 尚未持有這檔 → 以 nil 表示,不是錯誤
            return nil
        }
    }

    func buy(symbol: String, shares: Int, price: Double?, broker: String?) async throws -> TradeResult {
        let result: TradeResult = try await APIClient.shared.requestBody(
            "/portfolio/holdings/\(symbol)/buy",
            body: TradeRequestBody(shares: shares, price: price, broker: broker)
        )
        postDataChanged(.holdingsDidChange)
        return result
    }

    func sell(symbol: String, shares: Int, price: Double?, broker: String?) async throws -> TradeResult {
        let result: TradeResult = try await APIClient.shared.requestBody(
            "/portfolio/holdings/\(symbol)/sell",
            body: TradeRequestBody(shares: shares, price: price, broker: broker)
        )
        postDataChanged(.holdingsDidChange)
        return result
    }

    func override(symbol: String, shares: Int, broker: String?) async throws -> TradeResult {
        let result: TradeResult = try await APIClient.shared.requestBody(
            "/portfolio/holdings/\(symbol)/override",
            body: OverrideRequestBody(shares: shares, broker: broker)
        )
        postDataChanged(.holdingsDidChange)
        return result
    }

    func restore(symbol: String) async throws -> TradeResult {
        let result: TradeResult = try await APIClient.shared.request("/portfolio/holdings/\(symbol)/restore", method: "POST")
        postDataChanged(.holdingsDidChange)
        return result
    }

    func importMerge(decisions: [MergeDecision]) async throws -> ImportMergeResult {
        let result: ImportMergeResult = try await APIClient.shared.requestBody(
            "/portfolio/import/merge",
            body: ImportMergeRequestBody(decisions: decisions)
        )
        postDataChanged(.holdingsDidChange)
        return result
    }

    func getActivities(symbol: String) async throws -> [HoldingActivity] {
        return try await APIClient.shared.request("/portfolio/holdings/\(symbol)/activities", method: "GET")
    }

    func deleteActivity(id: String) async throws {
        let _: Bool = try await APIClient.shared.request("/portfolio/activities/\(id)", method: "DELETE")
        postDataChanged(.holdingsDidChange)
    }

    func deleteLot(id: String) async throws {
        // 分帳就是一筆 PortfolioItem,沿用既有刪除端點
        let _: Bool = try await APIClient.shared.request("/portfolio/items/\(id)", method: "DELETE")
        postDataChanged(.holdingsDidChange)
    }

    func updateLot(id: String, broker: String?, shares: Int, price: Double?) async throws {
        // 分帳就是一筆 PortfolioItem,直接依 id 更新(含改券商名),不走合併邏輯
        let _: LotUpdateResult = try await APIClient.shared.requestBody(
            "/portfolio/items/\(id)", method: "PATCH",
            body: LotUpdateBody(broker: broker, shares: shares, costPrice: price)
        )
        postDataChanged(.holdingsDidChange)
    }
}

private struct LotUpdateBody: Encodable {
    let broker: String?
    let shares: Int
    let costPrice: Double?
}

/// PATCH 回傳 PortfolioItemRead,前端更新後會重新 load,這裡只需能解碼
private struct LotUpdateResult: Codable {
    let id: String
}

// MARK: - Remote Privacy Service(隱私儀表板 · spec 05)
class RemotePrivacyService: PrivacyServiceProtocol {
    func getSummary() async throws -> PrivacySummary {
        return try await APIClient.shared.request("/privacy/summary", method: "GET")
    }

    func deleteAllData() async throws -> PrivacySummary {
        let result: DeleteAllResult = try await APIClient.shared.request("/privacy/all", method: "DELETE")
        postDataChanged(.holdingsDidChange)
        postDataChanged(.watchlistDidChange)
        return result.deleted
    }
}

// MARK: - Remote Stock Service
class RemoteStockService: StockServiceProtocol {
    func searchStocks(keyword: String) async throws -> [Stock] {
        let encodedKeyword = keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return try await APIClient.shared.request("/stocks/search?keyword=\(encodedKeyword)", method: "GET")
    }

    func aiScreenStocks(query: String) async throws -> AiScreenResult {
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return try await APIClient.shared.request("/stocks/ai-screen?query=\(encodedQuery)", method: "GET")
    }
    
    func getDailyPrice(symbol: String) async throws -> StockDailyPrice {
        return try await APIClient.shared.request("/stocks/\(symbol)/daily", method: "GET")
    }
    
    func getRecommendations(symbol: String) async throws -> [RecommendedStock] {
        return try await APIClient.shared.request("/recommendations/stocks?symbol=\(symbol)", method: "GET")
    }
}

// MARK: - Remote Watchlist Service(觀察清單 · spec 05)

struct WatchlistCreateBody: Encodable {
    let name: String
    let color: String?
}

struct WatchItemAddBody: Encodable {
    let symbol: String
}

struct ConvertRequestBody: Encodable {
    let shares: Int
    let price: Double?
}

class RemoteWatchlistService: WatchlistServiceProtocol {
    func getIndex() async throws -> WatchlistIndex {
        return try await APIClient.shared.request("/watchlists", method: "GET")
    }

    func createWatchlist(name: String, color: String?) async throws -> WatchlistSummary {
        let result: WatchlistSummary = try await APIClient.shared.requestBody(
            "/watchlists", body: WatchlistCreateBody(name: name, color: color)
        )
        postDataChanged(.watchlistDidChange)
        return result
    }

    func deleteWatchlist(id: String) async throws {
        let _: Bool = try await APIClient.shared.request("/watchlists/\(id)", method: "DELETE")
        postDataChanged(.watchlistDidChange)
    }

    func getDetail(id: String) async throws -> WatchlistDetail {
        return try await APIClient.shared.request("/watchlists/\(id)", method: "GET")
    }

    func addItem(watchlistId: String, symbol: String) async throws -> WatchStock {
        let result: WatchStock = try await APIClient.shared.requestBody(
            "/watchlists/\(watchlistId)/items", body: WatchItemAddBody(symbol: symbol)
        )
        postDataChanged(.watchlistDidChange)
        return result
    }

    func removeItem(watchlistId: String, symbol: String) async throws {
        let _: Bool = try await APIClient.shared.request(
            "/watchlists/\(watchlistId)/items/\(symbol)", method: "DELETE"
        )
        postDataChanged(.watchlistDidChange)
    }

    func convertToHolding(watchlistId: String, symbol: String, shares: Int, price: Double?) async throws -> ConvertResult {
        let result: ConvertResult = try await APIClient.shared.requestBody(
            "/watchlists/\(watchlistId)/items/\(symbol)/convert",
            body: ConvertRequestBody(shares: shares, price: price)
        )
        // 轉持股同時動到觀察清單與持股兩邊
        postDataChanged(.watchlistDidChange)
        postDataChanged(.holdingsDidChange)
        return result
    }

    func getAnalysis(watchlistId: String?) async throws -> WatchlistAnalysis {
        let query = watchlistId.map { "?watchlist_id=\($0)" } ?? ""
        return try await APIClient.shared.request("/watchlists/analysis\(query)", method: "GET")
    }

    func getWatchInsights() async throws -> WatchInsightList {
        return try await APIClient.shared.request("/watchlists/insights", method: "GET")
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

// MARK: - Remote Fortune Service(每日御神籤,取代原每日抽卡)
class RemoteFortuneService: FortuneServiceProtocol {
    func drawFortune(force: Bool) async throws -> FortuneResult {
        let query = force ? "?force=true" : ""
        return try await APIClient.shared.request("/fortune/draw\(query)", method: "POST")
    }

    func getTodayFortune() async throws -> FortuneResult? {
        do {
            let result: FortuneResult = try await APIClient.shared.request("/fortune/today", method: "GET")
            return result
        } catch APIError.invalidResponse(_, 200) {
            // 200 + data: null = 今天還沒抽 → 顯示 12a 搖籤入口,不是錯誤
            return nil
        }
    }
}

// MARK: - Remote Daily Pack Service(每日抽卡包 + AI 信任系統 · spec 06)
class RemoteDailyPackService: DailyPackServiceProtocol {
    func getTodayPack(force: Bool) async throws -> DailyPack {
        let query = force ? "?force=true" : ""
        return try await APIClient.shared.request("/pack/today\(query)", method: "GET")
    }

    func markOpened() async throws {
        let _: Bool = try await APIClient.shared.request("/pack/open", method: "POST")
    }

    func getShelf() async throws -> PackShelf {
        return try await APIClient.shared.request("/pack/shelf", method: "GET")
    }

    func getWeeklyCheckup() async throws -> WeeklyCheckup {
        return try await APIClient.shared.request("/pack/weekly-checkup", method: "GET")
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

// MARK: - Remote Investment Profile Service(投資風格 16a–16e)
class RemoteInvestmentProfileService: InvestmentProfileServiceProtocol {
    func getQuestionnaire() async throws -> QuestionnaireRead {
        return try await APIClient.shared.request("/investment-profile/questionnaire", method: "GET")
    }

    func submitQuestionnaire(answers: [String: String]) async throws -> InvestmentProfileRead {
        return try await APIClient.shared.requestBody("/investment-profile/questionnaire", method: "PUT", body: answers)
    }

    func getProfile() async throws -> InvestmentProfileRead {
        return try await APIClient.shared.request("/investment-profile", method: "GET")
    }

    func getHistory(limit: Int) async throws -> [HabitSnapshotRead] {
        return try await APIClient.shared.request("/investment-profile/history?limit=\(limit)", method: "GET")
    }

    func refresh() async throws -> HabitSnapshotRead {
        return try await APIClient.shared.request("/investment-profile/refresh", method: "POST")
    }

    func getPromptContext() async throws -> PromptContextRead {
        return try await APIClient.shared.request("/investment-profile/prompt-context", method: "GET")
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
