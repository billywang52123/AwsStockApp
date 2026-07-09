import Foundation
import SwiftUI

// MARK: - 觀察清單(spec 05 · 11a–11g)

/// 11a 清單切換選單:持股檔數 + 全部觀察清單
struct WatchlistIndex: Codable, Hashable {
    let holdingCount: Int
    let watchlists: [WatchlistSummary]
}

struct WatchlistSummary: Codable, Hashable, Identifiable {
    let id: String
    let name: String
    let color: String?
    let stockCount: Int

    var tintColor: Color {
        guard let color, !color.isEmpty else { return AppColor.amberNumber }
        return Color(hex: color)
    }
}

/// 11c 觀察清單頁
struct WatchlistDetail: Codable, Hashable {
    let id: String
    let name: String
    let color: String?
    let stockCount: Int
    let averageScore: Int
    let bullishCount: Int
    let neutralCount: Int
    let cautionCount: Int
    let items: [WatchStock]
}

struct WatchStock: Codable, Hashable, Identifiable {
    var id: String { symbol }
    let symbol: String
    let name: String
    let industry: String
    let closePrice: Double?
    let changePercent: Double
    let aiScore: Int
    let outlook: Outlook
    let headline: String
}

/// 11d 轉入庫存
struct ConvertResult: Codable, Hashable {
    let symbol: String
    let name: String
    let shares: Int
    let watchlistName: String
    let totalShares: Int
    let avgPrice: Double?
}

/// 11e 觀察清單分析
struct WatchlistAnalysis: Codable, Hashable {
    let watchCount: Int
    let averageScore: Int
    let trendNote: String
    let bullishCount: Int
    let neutralCount: Int
    let cautionCount: Int
    let exposure: [ExposureSegment]
    let exposureNote: String
    let overlapNotice: OverlapNotice?
}

struct OverlapNotice: Codable, Hashable {
    let title: String
    let body: String
    let highlight: String
    let plainTalk: String
}

/// 11f 觀點「觀察清單」分頁
struct WatchInsightList: Codable, Hashable {
    let bullishCount: Int
    let neutralCount: Int
    let cautionCount: Int
    let items: [WatchInsightItem]
}

struct WatchInsightItem: Codable, Hashable, Identifiable {
    var id: String { symbol + watchlistName }
    let symbol: String
    let name: String
    let industry: String
    let watchlistName: String
    let aiScore: Int
    let outlook: Outlook
    let headline: String
}

/// 11g 推薦卡星標:推薦股票 + 觀察清單狀態
struct RecommendedStock: Codable, Hashable, Identifiable {
    var id: String { symbol }
    let symbol: String
    let name: String
    let market: Market
    let industry: String?
    let inWatchlist: Bool
    let watchlistId: String?
    let watchlistName: String?
}

// MARK: - 11b 清單顏色(5 色圓點,存 hex 供 icon 區分清單)

enum WatchlistColorOption: String, CaseIterable, Identifiable {
    case amber = "#D9A264"
    case violet = "#7B7FD4"
    case green = "#6E9A7F"
    case rose = "#C97F7F"
    case lilac = "#A493D9"

    var id: String { rawValue }
    var color: Color { Color(hex: rawValue) }
}
