import Foundation
import SwiftUI

// MARK: - 每日御神籤(spec 第十二輪 14a–14d:老籤紙 · 發光書法 · 煙/光自籤內漂出)

struct FortuneResult: Codable, Hashable {
    let stickNumber: Int
    let stickLabel: String          // 「第十四籤」
    let overallLevel: FortuneLevel  // 綜合籤等(各持股加權)
    let levelNote: String           // 籤等一句話
    let holdings: [FortuneHolding]  // 「持股與狀態」
    let summary: String             // 「說明」
    let stance: String              // 今天的節奏
    let stanceNote: String
    let notices: [String]           // 「注意事項」
    let alreadyDrawn: Bool
    let session: String?            // day = 日盤籤 / night = 夜盤籤(舊版後端沒有此欄)

    var sessionType: FortuneSession { FortuneSession(rawValue: session ?? "day") ?? .day }
}

/// 抽籤時段:日盤(台股 13:30 收盤後)/ 夜盤(美股收盤,次日 05:00 起)
enum FortuneSession: String {
    case day
    case night

    var label: String { self == .day ? "日盤籤" : "夜盤籤" }

    /// 結果頁「已抽」pill:提示下一時段的開放時間
    var drawnNote: String {
        self == .day ? "日盤籤已抽 · 夜盤 05:00 開放" : "夜盤籤已抽 · 日盤 13:30 開放"
    }

    /// 現在時段(台灣時間):13:30 起~次日 05:00 日盤;05:00~13:30 夜盤
    static func current(now: Date = Date()) -> FortuneSession {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Taipei") ?? .current
        let comps = calendar.dateComponents([.hour, .minute], from: now)
        let minutes = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
        if minutes >= 13 * 60 + 30 || minutes < 5 * 60 { return .day }
        return .night
    }
}

struct FortuneHolding: Codable, Hashable, Identifiable {
    var id: String { symbol }
    let symbol: String
    let name: String
    let level: FortuneLevel
    let comment: String
}

/// 六級籤等 — 最終方向(README 14a–14d):「金=吉 / 紅=凶」的御神籤配色
enum FortuneLevel: String, Codable, CaseIterable {
    case daikichi = "大吉"
    case kichi = "吉"
    case shokichi = "小吉"
    case shokyo = "小凶"
    case kyo = "凶"
    case daikyo = "大凶"

    var label: String { rawValue }

    /// 14c/14d 開籤光效:正 = 金光強度、負 = 黑煙濃度(1–3 級)
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

    /// 籤紙上各籤等的書法字色(README 六級籤等色票;依頁面主題微調)
    func paperInk(auspiciousTheme: Bool) -> Color {
        switch self {
        case .daikichi: return Color(hex: "B8860E")
        case .kichi: return Color(hex: "C29A2E")
        case .shokichi: return Color(hex: auspiciousTheme ? "A98A3E" : "9A7A2E")
        case .shokyo: return Color(hex: "7A6A88")
        case .kyo: return Color(hex: "B0261B")
        case .daikyo: return Color(hex: "8E1A11")
        }
    }

    /// 13c 副標的短語(結果頁副標「今日綜合運勢 · …」)
    var levelHint: String {
        switch self {
        case .daikichi: return "大方向順風"
        case .kichi: return "整體安穩"
        case .shokichi: return "穩中帶光"
        case .shokyo: return "短線有雜音"
        case .kyo: return "今天逆風"
        case .daikyo: return "先別做決定"
        }
    }
}

// MARK: - 14c/14d 頁面主題(2026-07 配色定調:米黃暖紙底,非黑底)
// 大凶米黃紙 + 血紅書法 / 大吉金黃紙 + 深金書法;墨煙黑雨落在紙面呈「墨暈」感。

struct FortuneTheme {
    let isAuspicious: Bool

    init(level: FortuneLevel) {
        self.isAuspicious = level.isAuspicious
    }

    // 暖紙背景(radial 由內而外;略深於籤紙以突顯籤紙)
    var bgInner: Color { Color(hex: isAuspicious ? "EFE2C0" : "E7D9BC") }
    var bgMid: Color { Color(hex: isAuspicious ? "E3D3AA" : "DBCCA9") }
    var bgOuter: Color { Color(hex: isAuspicious ? "D6C48E" : "CDBC94") }

    // 標題書法字與光暈(金色已調深以在米黃底上維持對比)
    var titleColor: Color { Color(hex: isAuspicious ? "C0891A" : "D6301F") }
    var titleGlowStrong: Color {
        isAuspicious ? Color(hex: "C89628").opacity(0.6) : Color(hex: "D6301F").opacity(0.9)
    }
    var titleGlowSoft: Color {
        isAuspicious ? Color(hex: "966E14").opacity(0.4) : Color(hex: "96140C").opacity(0.8)
    }
    var subtitleColor: Color { Color(hex: isAuspicious ? "9E7526" : "9A4438") }

    // 老籤紙
    var paperTop: Color { Color(hex: isAuspicious ? "EFE4C4" : "E7DABB") }
    var paperMid: Color { Color(hex: isAuspicious ? "E1D0A6" : "D7C39C") }
    var paperBottom: Color { Color(hex: isAuspicious ? "D2BC8A" : "C6AE80") }

    /// 主色(框線、標頭橫幅、欄位標題、膠囊)
    var primary: Color { Color(hex: isAuspicious ? "9A6B1E" : "7A1E14") }
    /// 標頭橫幅與膠囊上的紙色文字
    var bannerText: Color { Color(hex: isAuspicious ? "F7EDCF" : "EEE3C8") }
    /// 注意事項圓點
    var bulletColor: Color { Color(hex: isAuspicious ? "B8860E" : "B0261B") }

    // 特效(雨絲/煙光;金光在淺底上用深金)
    var rainColor: Color {
        isAuspicious ? Color(hex: "F0CD78").opacity(0.7) : Color(hex: "0E0505").opacity(0.75)
    }
    var puffColor: Color {
        isAuspicious ? Color(hex: "D29E34").opacity(0.55) : Color(hex: "241C1A").opacity(0.5)
    }
    var emberGlow: Color {
        isAuspicious ? Color(hex: "E6B446").opacity(0.42) : Color(hex: "B0261B").opacity(0.4)
    }
}
