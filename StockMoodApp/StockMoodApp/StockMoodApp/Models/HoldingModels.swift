import Foundation

// MARK: - 持股(券商分帳聚合)· spec 04

/// 單一券商分帳(9e BrokerLotRow 的資料來源)
struct BrokerLot: Identifiable, Codable, Hashable {
    let id: String
    let broker: String?
    let shares: Int
    let avgPrice: Double?
    let source: String
    let createdAt: Date
    let updatedAt: Date

    var brokerDisplayName: String { broker ?? "未指定券商" }
}

/// 聚合後的一檔持股:總股數 + 加權均價 + 各分帳
struct Holding: Identifiable, Codable, Hashable {
    var id: String { symbol }
    let symbol: String
    let name: String
    let industry: String?
    let totalShares: Int
    let avgPrice: Double?
    /// 有分帳缺買價 → 列表提示「補填買價」(spec 9b 僅更新股數模式)
    let avgPriceIncomplete: Bool
    let lots: [BrokerLot]
}

/// 買進 / 賣出 / 覆蓋的結果
struct TradeResult: Codable, Hashable {
    let holding: Holding?
    let realizedPnl: Double?
    let realizedPnlPercent: Double?
    /// 全部賣出 → 已移到「已出場」,可用 restore 還原(undo toast)
    let exited: Bool
}

/// 9e 最近異動紀錄
struct HoldingActivity: Identifiable, Codable, Hashable {
    let id: String
    let symbol: String
    let activityType: String   // buy / sell / override / import / exit / restore
    let sharesDelta: Int
    let price: Double?
    let broker: String?
    let realizedPnl: Double?
    let avgPriceAfter: Double?
    let createdAt: Date
}

// MARK: - 9d 匯入合併決策

enum MergeAction: String, Codable {
    case addLot = "add_lot"              // 不同券商 → 新分帳(分帳加總)
    case replaceBroker = "replace_broker" // 同券商 → 視為最新快照,取代該分帳
    case mergeAdd = "merge_add"           // 與該券商分帳加總攤平
    case replaceAll = "replace_all"       // 取代全部(destructive)
    case skip = "skip"
}

struct MergeDecision: Codable {
    let symbol: String
    let shares: Int
    let cost: Double?
    let broker: String?
    let action: String
}

struct ImportMergeRequestBody: Codable {
    let decisions: [MergeDecision]
}

struct ImportMergeResult: Codable {
    let updatedCount: Int
    let holdings: [Holding]
}

// MARK: - Request bodies

struct TradeRequestBody: Codable {
    let shares: Int
    let price: Double?
    let broker: String?
}

struct OverrideRequestBody: Codable {
    let shares: Int
    let broker: String?
}

// MARK: - 常用券商清單(9d 改來源 / 9e 新增分帳的選單)

enum TaiwanBrokers {
    static let common = [
        "富邦證券", "國泰證券", "元大證券", "凱基證券", "永豐金證券",
        "玉山證券", "台新證券", "中國信託證券", "群益金鼎證券", "第一金證券",
    ]
}

// MARK: - 語音輸入持股(spec 08 · 19a–19c)

/// AI 從逐字稿解析出的一筆持股;confidence == "low" 表示對不到台股代號(19c 金色卡)。
struct VoiceParsedHolding: Codable, Hashable, Identifiable {
    var id: String { symbol ?? mention }
    let symbol: String?
    let name: String?
    /// 句中對這檔股票的原話稱呼
    let mention: String
    /// 換算後股數(「兩張」→ 2000);句子沒提到為 nil
    let shares: Int?
    /// 每股成本;沒提到為 nil(選填,不擋加入)
    let costPrice: Double?
    /// 口語換算依據註記(19c 卡底小字,例:「『兩張』= 2,000 股」)
    let note: String?
    let confidence: String

    var isLowConfidence: Bool { confidence == "low" }
}

struct VoiceParseResult: Codable, Hashable {
    /// 原句回顯(19c 引用盒逐字不省略)
    let transcript: String
    let items: [VoiceParsedHolding]
    /// 解析不到東西時的安撫文案
    let message: String?
}
