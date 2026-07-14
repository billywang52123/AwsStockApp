import Foundation

// MARK: - 每日抽卡包 + AI 信任系統(spec 06 · 15a–15k,取代御神籤)
// 三張卡固定順序(不可亂序,順序本身是信任設計):事實 → 推論 → 陪伴

/// 出處 chip(15i):所有 AI 結論句尾掛的可點小標籤
struct SourceChip: Codable, Hashable, Identifiable {
    var id: String { label + field + rawValue }
    let label: String       // 「📊 收盤行情」
    let field: String       // 使用的欄位
    let rawValue: String    // 原始數值
    let formula: String     // 計算方式
    let dataDate: String    // 資料日期
    let source: String      // 資料來源
}

/// 事實卡個股展開列中的一行數據
struct FactRow: Codable, Hashable, Identifiable {
    var id: String { label + value }
    let label: String
    let value: String
    let chip: SourceChip?
}

/// 事實卡個股明細(15f ExpandableStockRow)
struct FactStock: Codable, Hashable, Identifiable {
    var id: String { symbol }
    let symbol: String
    let name: String
    let changePercent: Double
    let rows: [FactRow]
    let expandedDefault: Bool
}

/// 閃卡(15f):觸發條件是寫死的數據事件,絕不是 AI 判斷
struct PackFlashcard: Codable, Hashable {
    let eventText: String
    let chip: SourceChip
}

struct FactCardData: Codable, Hashable {
    let totalValueText: String
    let totalChangePercent: Double
    let totalChip: SourceChip
    let stocks: [FactStock]
    let footnote: String
    let flashcard: PackFlashcard?
}

/// 名詞小卡(15g 虛線術語)
struct GlossaryTerm: Codable, Hashable, Identifiable {
    var id: String { term }
    let term: String
    let definition: String
}

/// 推理鏈步驟(15g):每步是數字組合,非形容詞
struct ReasoningStep: Codable, Hashable, Identifiable {
    var id: Int { number }
    let number: Int
    let text: String
    let chip: SourceChip?
    let glossary: GlossaryTerm?
}

struct InferenceCardData: Codable, Hashable {
    let conclusion: String
    let terms: [GlossaryTerm]
    let steps: [ReasoningStep]
    let caveat: String
}

struct CompanionCardData: Codable, Hashable {
    let text: String
    let signature: String
    let dayCount: Int
}

/// 15a「今天為什麼值得看」卡
struct WhyToday: Codable, Hashable {
    let text: String
    let chips: [SourceChip]
}

struct DailyPack: Codable, Hashable {
    let dateText: String        // 「2025/12/31 · 週三」
    let dataDate: String        // footer 揭露用
    let holdingsCount: Int
    let totalValueText: String
    let whyToday: WhyToday
    let fact: FactCardData
    let inference: InferenceCardData
    let companion: CompanionCardData
    let opened: Bool
}

/// 三張核心卡的卡型(UI 導覽用;順序固定 1→2→3)
enum PackCardKind: Int, CaseIterable, Identifiable {
    case fact = 0
    case inference
    case companion

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .fact: return "事實卡"
        case .inference: return "推論卡"
        case .companion: return "陪伴卡"
        }
    }

    var tagText: String {
        switch self {
        case .fact: return "事實卡 · 可驗證"
        case .inference: return "AI 推論"
        case .companion: return "AI 陪伴訊息"
        }
    }
}

// MARK: - 15j 卡包架

struct ShelfPack: Codable, Hashable, Identifiable {
    var id: String { symbol }
    let symbol: String
    let name: String
    let industry: String
    let subtitle: String
    let hasNewInsight: Bool
    let insightNote: String?
}

/// 歷史卡片圖鑑小卡;kind: fact / inference / companion / flash
struct CollectionCard: Codable, Hashable, Identifiable {
    var id: String { kind + dateText }
    let kind: String
    let dateText: String
}

struct PackShelf: Codable, Hashable {
    let packs: [ShelfPack]
    let collectedCount: Int
    let recentCards: [CollectionCard]
    let moreCount: Int
}

// MARK: - 15k 週末體檢

/// 對帳列:上週說法 → 應驗(met)/未發生(miss),照實呈現
struct ReconciliationRow: Codable, Hashable, Identifiable {
    var id: String { statement }
    let statement: String
    let outcome: String     // met / miss
    let note: String
    let chip: SourceChip?

    var isMet: Bool { outcome == "met" }
}

struct CheckupTile: Codable, Hashable, Identifiable {
    var id: String { label }
    let label: String
    let value: String
    let note: String
}

struct WeeklyCheckup: Codable, Hashable {
    let weekLabel: String
    let metCount: Int
    let totalCount: Int
    let rows: [ReconciliationRow]
    let tiles: [CheckupTile]
    let specialPackNote: String
}
