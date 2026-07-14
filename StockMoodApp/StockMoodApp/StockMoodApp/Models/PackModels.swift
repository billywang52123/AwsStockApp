import Foundation

// MARK: - 每日抽卡包 + AI 信任系統(spec 06 · 15a–15k,取代御神籤)
// 三張卡固定順序(不可亂序,順序本身是信任設計):事實 → 推論 → 社群

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

/// 社群卡(15h · 同學會溫度計):討論量 vs 30 日均值、看多看空 vs 自身基準。
/// 鐵則:社群結構性偏多,只顯示相對自身歷史基準的變化,絕不顯示絕對多空比。
struct CommunityCardData: Codable, Hashable {
    let stockName: String            // 聚焦股名(同學會討論最熱的一檔)
    let stockSymbol: String
    let hasData: Bool                // 無同學會資料時顯示資料不足態
    let postsToday: Int              // 今日討論量(則)
    let postsBaseline: Double        // 30 日均值(則)
    let heatText: String             // 「討論熱度是這檔 30 日均值的 2.3 倍」
    let baselineTickPercent: Double  // 討論量條上白色刻度線位置(0–100)
    let sentimentShiftPercent: Double?   // 較自身基準偏多/空(百分點)
    let sentimentText: String?       // 「較自身基準偏多 +14%(多 118/空 17/中性 997)」
    let bullish: Int
    let bearish: Int
    let neutral: Int
    let note: String                 // 「社群情緒 ≠ 買賣訊號…」
    let chip: SourceChip?
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
    let communityCard: CommunityCardData
    let opened: Bool
}

/// 三張核心卡的卡型(UI 導覽用;順序固定 1→2→3)
enum PackCardKind: Int, CaseIterable, Identifiable {
    case fact = 0
    case inference
    case community

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .fact: return "事實卡"
        case .inference: return "AI 推論卡"
        case .community: return "社群卡"
        }
    }

    var tagText: String {
        switch self {
        case .fact: return "事實卡 · 可驗證"
        case .inference: return "AI 推論"
        case .community: return "社群卡 · 同學會"
        }
    }

    // ── 15e TCG 卡背素材 ──

    /// 徽記單字(實/推/氛)
    var emblemGlyph: String {
        switch self {
        case .fact: return "實"
        case .inference: return "推"
        case .community: return "氛"
        }
    }

    /// 飾線夾副標(可驗證數據 / AI 的判斷 / 同學會氣氛)
    var backSubtitle: String {
        switch self {
        case .fact: return "可驗證數據"
        case .inference: return "AI 的判斷"
        case .community: return "同學會氣氛"
        }
    }

    /// 羅馬數字序號
    var romanNumeral: String {
        switch self {
        case .fact: return "I"
        case .inference: return "II"
        case .community: return "III"
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

/// 歷史卡片圖鑑小卡;kind: fact / inference / community / flash(舊資料可能為 companion)
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
