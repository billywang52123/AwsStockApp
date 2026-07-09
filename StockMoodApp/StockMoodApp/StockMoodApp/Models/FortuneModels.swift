import Foundation
import SwiftUI

// MARK: - 每日御神籤(spec 第十輪 12a–12d + 第十一輪 13a–13d)

struct FortuneResult: Codable, Hashable {
    let stickNumber: Int
    let stickLabel: String          // 「第十四籤」
    let overallLevel: FortuneLevel  // 綜合籤等(各持股加權)
    let levelNote: String           // 籤等一句話(12d 語氣)
    let holdings: [FortuneHolding]  // 「持股與狀態」
    let summary: String             // 「說明」
    let stance: String              // 今天的節奏
    let stanceNote: String
    let notices: [String]           // 「注意事項」
    let alreadyDrawn: Bool
}

struct FortuneHolding: Codable, Hashable, Identifiable {
    var id: String { symbol }
    let symbol: String
    let name: String
    let level: FortuneLevel
    let comment: String
}

/// 六級籤等(12d tokens):紅偏吉 / 綠偏凶,呼應台股漲跌色
enum FortuneLevel: String, Codable, CaseIterable {
    case daikichi = "大吉"
    case kichi = "吉"
    case shokichi = "小吉"
    case shokyo = "小凶"
    case kyo = "凶"
    case daikyo = "大凶"

    var label: String { rawValue }

    var textColor: Color {
        switch self {
        case .daikichi: return Color(hex: "B0605C")
        case .kichi: return Color(hex: "C97F7F")
        case .shokichi: return Color(hex: "B0813F")
        case .shokyo: return Color(hex: "7A83A8")
        case .kyo: return Color(hex: "6E9A7F")
        case .daikyo: return Color(hex: "4F7A62")
        }
    }

    var bgTint: Color {
        switch self {
        case .daikichi: return Color(hex: "F5E3E3")
        case .kichi: return Color(hex: "F7E9E6")
        case .shokichi: return Color(hex: "FDF9F0")
        case .shokyo: return Color(hex: "EEF0F7")
        case .kyo: return Color(hex: "E4EEE7")
        case .daikyo: return Color(hex: "DFEAE3")
        }
    }

    /// 13d 開籤光效:正 = 金光強度、負 = 黑煙濃度(1–3 級)
    var revealIntensity: Int {
        switch self {
        case .daikichi: return 3
        case .kichi: return 2
        case .shokichi: return 1
        case .shokyo: return -1
        case .kyo: return -2
        case .daikyo: return -3
        }
    }

    var isAuspicious: Bool { revealIntensity > 0 }

    /// 13c 結果頁頂部狀態條文案
    var topBarNote: String {
        switch self {
        case .daikichi: return "今日綜合運勢 · 金光罩頂"
        case .kichi: return "今日綜合運勢 · 暖光相伴"
        case .shokichi: return "今日綜合運勢 · 微光穩穩"
        case .shokyo: return "今日綜合運勢 · 一縷輕煙"
        case .kyo: return "今日綜合運勢 · 逆風有煙"
        case .daikyo: return "今日綜合運勢 · 黑煙纏身"
        }
    }
}
