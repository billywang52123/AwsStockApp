import Foundation

struct Stock: Identifiable, Codable, Hashable {
    var id: String { symbol }
    let symbol: String
    let name: String
    let market: Market
    let industry: String?
}

enum Market: String, Codable {
    case tw = "TW"
    case us = "US"
}

// MARK: - AI 找股(觀察清單「加入觀察股」的 AI 搜尋)
/// 後端已逐檔驗證過的候選標的;reason 為 AI 對條件關聯的描述(不含操作字眼)。
struct AiScreenItem: Identifiable, Codable, Hashable {
    var id: String { symbol }
    let symbol: String
    let name: String
    let industry: String?
    let closePrice: Double?
    let changePercent: Double?
    let reason: String
}

struct AiScreenResult: Codable, Hashable {
    let items: [AiScreenItem]
    let note: String?
}

struct PortfolioItem: Identifiable, Codable, Hashable {
    let id: UUID
    let symbol: String
    let name: String
    let costPrice: Double?
    let shares: Int?
    /// 這筆持股所屬券商(手動新增/匯入時由用戶選定);nil = 未指定
    let broker: String?
    let createdAt: Date

    init(id: UUID, symbol: String, name: String, costPrice: Double?, shares: Int?,
         broker: String? = nil, createdAt: Date) {
        self.id = id
        self.symbol = symbol
        self.name = name
        self.costPrice = costPrice
        self.shares = shares
        self.broker = broker
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        symbol = try container.decode(String.self, forKey: .symbol)
        // 後端 schema 的 name 允許 null;缺名時退回用代號,不讓整份清單解碼失敗
        name = (try? container.decode(String.self, forKey: .name)) ?? symbol
        costPrice = try container.decodeIfPresent(Double.self, forKey: .costPrice)
        shares = try container.decodeIfPresent(Int.self, forKey: .shares)
        broker = try container.decodeIfPresent(String.self, forKey: .broker)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
    }
}

struct StockDailyPrice: Codable, Hashable {
    let symbol: String
    let tradeDate: Date
    let closePrice: Double
    let changePercent: Double
    let volume: Double?
}

struct AnxietyResult: Codable, Hashable {
    let score: Int
    let level: String
    let message: String
    let mainReason: String
    let riskLabel: String
}

struct DailySummary: Codable, Hashable {
    let title: String
    let summary: String
    let explanation: String
    let portfolioImpactItems: [PortfolioImpactItem]
    let disclaimer: String
}

struct PortfolioImpactItem: Identifiable, Codable, Hashable {
    var id: String { symbol }
    let symbol: String
    let name: String
    let changePercent: Double
    let impactLevel: ImpactLevel
    let reason: String
}

enum ImpactLevel: String, Codable {
    case high = "HIGH"
    case medium = "MEDIUM"
    case low = "LOW"
}

struct MarketCompareResult: Codable, Hashable {
    let portfolioChangePercent: Double
    let marketChangePercent: Double
    let message: String
}

struct ReminderSetting: Codable, Hashable {
    var enabled: Bool
    var timeSlot: ReminderTimeSlot
    var items: ReminderItems
}

enum ReminderTimeSlot: String, Codable {
    case morning = "MORNING"
    case noon = "NOON"
    case afterMarket = "AFTER_MARKET"
    case evening = "EVENING"
}

struct ReminderItems: Codable, Hashable {
    var anxietyScore: Bool
    var dailyCard: Bool
    var volatilityAlert: Bool
}
