import SwiftUI

// MARK: - 投資風格與投資習慣(spec 07 · 16a–16e,對接 /investment-profile API)

// MARK: 16a 問卷

struct QuestionnaireRead: Codable, Hashable {
    let version: Int
    let completed: Bool
    let currentAnswers: [String: String]?
    let questions: [QuestionnaireQuestion]
}

struct QuestionnaireQuestion: Codable, Hashable, Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let options: [QuestionnaireOption]
}

struct QuestionnaireOption: Codable, Hashable, Identifiable {
    var id: String { code }
    let code: String
    let label: String
    let description: String
}

// MARK: 16b / 16d 風格與習慣

struct StyleRead: Codable, Hashable {
    let code: String
    let label: String
    let summary: String
}

struct HabitRead: Codable, Hashable {
    let code: String
    let label: String
    let summary: String
}

/// 四維度分數(0–100):風險承受 / 調整頻率 / 持有期間 / 決策依據
struct StyleDimensions: Codable, Hashable {
    let risk: Int
    let activity: Int
    let horizon: Int
    let evidence: Int
}

struct PortfolioHabitMetrics: Codable, Hashable {
    let holdingCount: Int
    let industryCount: Int
    let topHoldingWeight: Double
    let top3Weight: Double
    let techWeight: Double
    let activityCount30d: Int
    let buyCount30d: Int
    let sellCount30d: Int
    let costCompletionRatio: Double
}

struct InvestmentProfileRead: Codable, Hashable {
    let questionnaireCompleted: Bool
    let questionnaireVersion: Int
    let preferenceStyle: StyleRead
    let observedStyle: StyleRead
    let investmentHabit: HabitRead
    let styleDimensions: StyleDimensions
    let portfolioMetrics: PortfolioHabitMetrics
    let latestChange: String
    let updatedAt: Date?
    let promptVersion: String
}

// MARK: 16e 習慣快照(風格轉變時間軸)

struct HabitSnapshotRead: Codable, Hashable, Identifiable {
    let id: String
    let trigger: String
    let preferenceStyleCode: String
    let observedStyle: StyleRead
    let investmentHabit: HabitRead
    let portfolioMetrics: PortfolioHabitMetrics
    let changeSummary: String
    let createdAt: Date
}

// MARK: 16c Prompt context(僅顯示用,注入在後端完成)

struct PromptContextRead: Codable, Hashable {
    let promptVersion: String
    let preferenceStyle: StyleRead
    let observedStyle: StyleRead
    let investmentHabit: HabitRead
    let appliedPrinciples: [String]
    let portfolioFacts: [String: Double]
    let promptText: String
}

// MARK: - 風格主色與維度文案(UI 對應)

enum InvestStyleTheme {
    /// 各分型主色(降飽和,依 spec 07 四型色系對應後端分型)
    static func color(for code: String) -> Color {
        switch code {
        case "conservative_guardian": return AppColor.downText          // 綠:穩健守護
        case "steady_balancer": return AppColor.primary                 // 紫:穩健平衡
        case "growth_explorer": return AppColor.amberNumber             // amber:長期成長
        case "active_opportunist", "focused_growth": return Color(hex: "B0759A") // 莓紫:主動/集中
        case "diversified_balancer": return AppColor.downStrong
        default: return AppColor.inkQuaternary                          // 未分類
        }
    }

    /// 16b 風格大卡 150° 漸層
    static func gradient(for code: String) -> [Color] {
        switch code {
        case "conservative_guardian":
            return [Color(hex: "82AC92"), Color(hex: "5F8A70"), Color(hex: "466A55")]
        case "steady_balancer":
            return [Color(hex: "8B8FE0"), Color(hex: "6C70C4"), Color(hex: "54589E")]
        case "growth_explorer":
            return [Color(hex: "E0B072"), Color(hex: "C08F4F"), Color(hex: "976F3B")]
        case "active_opportunist", "focused_growth":
            return [Color(hex: "C58BAD"), Color(hex: "A66489"), Color(hex: "7E4A67")]
        case "diversified_balancer":
            return [Color(hex: "82AC92"), Color(hex: "5F8A70"), Color(hex: "466A55")]
        default:
            return [Color(hex: "B4AFA5"), Color(hex: "9B968C"), Color(hex: "7E7A71")]
        }
    }

    /// 四維度顯示名與白話值(依 0–100 分桶)
    static let axes: [(key: String, name: String)] = [
        ("risk", "風險承受"),
        ("horizon", "持有期間"),
        ("activity", "調整頻率"),
        ("evidence", "決策依據"),
    ]

    static func value(of dimensions: StyleDimensions, key: String) -> Int {
        switch key {
        case "risk": return dimensions.risk
        case "horizon": return dimensions.horizon
        case "activity": return dimensions.activity
        default: return dimensions.evidence
        }
    }

    static func valueLabel(key: String, score: Int) -> String {
        switch key {
        case "risk":
            return score < 35 ? "偏保守" : (score < 65 ? "中等" : "偏積極")
        case "horizon":
            return score < 35 ? "偏短期" : (score < 65 ? "中期" : "偏長期")
        case "activity":
            return score < 35 ? "很少調整" : (score < 65 ? "偶爾調整" : "經常調整")
        default:
            return score < 50 ? "重整體感受" : (score < 75 ? "重事件脈絡" : "重數據驗證")
        }
    }
}
