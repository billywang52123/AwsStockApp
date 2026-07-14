import Foundation
import SwiftUI

// MARK: - 庫存分析(8a / 8b / 8c)

struct PortfolioAnalysis: Codable, Hashable {
    let totalMarketValue: Double
    let totalCost: Double
    let unrealizedPnl: Double
    let unrealizedPnlPercent: Double
    let holdingsCount: Int
    let riskScore: Int
    let riskNote: String
    let anxietyScore: Int
    let anxietyNote: String
    let exposure: [ExposureSegment]
    let techExposurePercent: Double
    let exposureNote: String
    let holdings: [HoldingDetail]
    let riskNotices: [RiskNotice]
}

struct ExposureSegment: Codable, Hashable, Identifiable {
    var id: String { industry }
    let industry: String
    let percent: Double
}

struct HoldingDetail: Codable, Hashable, Identifiable {
    let id: String
    let symbol: String
    let name: String
    let industry: String
    let shares: Int?
    let costPrice: Double?
    let closePrice: Double?
    let marketValue: Double
    let pnl: Double
    let pnlPercent: Double
    let weightPercent: Double
    let changePercent: Double
}

struct RiskNotice: Codable, Hashable, Identifiable {
    var id: String { title }
    let severity: NoticeSeverity
    let badge: String
    let title: String
    let body: String
    let highlight: String
    let plainTalk: String
}

enum NoticeSeverity: String, Codable {
    case rose
    case amber
}

// MARK: - 個股 AI 觀點(8d / 8e)

struct InsightList: Codable, Hashable {
    let bullishCount: Int
    let neutralCount: Int
    let cautionCount: Int
    let items: [StockInsightSummary]
}

struct StockInsightSummary: Codable, Hashable, Identifiable {
    var id: String { symbol }
    let symbol: String
    let name: String
    let industry: String
    let weightPercent: Double
    let outlook: Outlook
    let outlookScore: Int
    let headline: String
}

enum Outlook: String, Codable, CaseIterable {
    case bullish
    case neutral
    case caution

    var label: String {
        switch self {
        case .bullish: return "看好"
        case .neutral: return "中性"
        case .caution: return "短線留意"
        }
    }

    var textColor: Color {
        switch self {
        case .bullish: return AppColor.upStrong
        case .neutral: return AppColor.neutralText
        case .caution: return AppColor.downStrong
        }
    }

    var bgColor: Color {
        switch self {
        case .bullish: return AppColor.upBgTint
        case .neutral: return AppColor.neutralBgTint
        case .caution: return AppColor.downBgTint
        }
    }
}

struct StockInsightDetail: Codable, Hashable {
    let symbol: String
    let name: String
    let industry: String
    let outlook: Outlook
    let outlookScore: Int
    let stanceLabel: String
    let summary: String
    let signals: [NewsSignal]
    let plainSummary: String
}

struct NewsSignal: Codable, Hashable, Identifiable {
    var id: String { source + text }
    let source: String
    let direction: SignalDirection
    let directionLabel: String
    let text: String
    let explanation: String
    let calculation: String
    let rule: String
    let dataSource: String
    let dataDate: String
}

enum SignalDirection: String, Codable {
    case bullish
    case bearish
    case neutral

    var color: Color {
        switch self {
        case .bullish: return AppColor.upStrong
        case .bearish: return AppColor.downStrong
        case .neutral: return AppColor.neutralText
        }
    }
}
