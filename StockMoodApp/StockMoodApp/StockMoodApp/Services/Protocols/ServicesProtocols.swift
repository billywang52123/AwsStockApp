import Foundation

protocol PortfolioServiceProtocol {
    func getPortfolioItems() async throws -> [PortfolioItem]
    func addPortfolioItem(_ item: PortfolioItem) async throws
    func deletePortfolioItem(id: UUID) async throws
    /// 語音輸入持股(spec 08):裝置端轉好的逐字稿 → AI 解析成結構化持股
    func parseVoiceHoldings(text: String) async throws -> VoiceParseResult
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
    func updateLot(id: String, broker: String?, shares: Int, price: Double?) async throws
}

/// 隱私儀表板(spec 05 · 10a)
protocol PrivacyServiceProtocol {
    func getSummary() async throws -> PrivacySummary
    func deleteAllData() async throws -> PrivacySummary
}

protocol StockServiceProtocol {
    func searchStocks(keyword: String) async throws -> [Stock]
    /// AI 找股:自然語言條件(如「殖利率 5% 以上的高股息」)→ 已驗證的候選名單
    func aiScreenStocks(query: String) async throws -> AiScreenResult
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

/// 每日抽卡包 + AI 信任系統(spec 06 · 15a–15k,取代御神籤)
protocol DailyPackServiceProtocol {
    /// force = true:丟棄今日包,依當下持股重算(重生測試用)
    func getTodayPack(force: Bool) async throws -> DailyPack
    /// 開包動畫看完(或跳過)後標記,之後開頁直達完成態
    func markOpened() async throws
    func getShelf() async throws -> PackShelf
    func getWeeklyCheckup() async throws -> WeeklyCheckup
}

/// 每日御神籤(spec 第十輪 12a–12d,已由每日抽卡包取代,保留存檔)
protocol FortuneServiceProtocol {
    /// force = true:丟棄今日籤,依當下持股重新求一支(重抽測試用)
    func drawFortune(force: Bool) async throws -> FortuneResult
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

/// 投資風格與投資習慣(spec 07 · 16a–16e)
protocol InvestmentProfileServiceProtocol {
    func getQuestionnaire() async throws -> QuestionnaireRead
    /// 交卷:answers 的 key 必須是題目 id(如 investment_horizon)、value 是選項 code
    func submitQuestionnaire(answers: [String: String]) async throws -> InvestmentProfileRead
    func getProfile() async throws -> InvestmentProfileRead
    func getHistory(limit: Int) async throws -> [HabitSnapshotRead]
    /// 手動重算習慣快照(正常買賣/匯入後後端會自動建立)
    func refresh() async throws -> HabitSnapshotRead
    func getPromptContext() async throws -> PromptContextRead
}
