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

struct PortfolioItem: Identifiable, Codable, Hashable {
    let id: UUID
    let symbol: String
    let name: String
    let costPrice: Double?
    let shares: Int?
    let createdAt: Date
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

struct DrawCardResult: Codable, Hashable {
    let cardType: DrawCardType
    let title: String
    let message: String
    let actionText: String
}

enum DrawCardType: String, Codable {
    case calmObserve = "CALM_OBSERVE"
    case marketImpact = "MARKET_IMPACT"
    case volatilityAlert = "VOLATILITY_ALERT"
    case stockEvent = "STOCK_EVENT"
    case confidenceRestore = "CONFIDENCE_RESTORE"
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
