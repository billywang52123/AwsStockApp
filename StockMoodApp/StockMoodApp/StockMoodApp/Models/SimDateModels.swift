import Foundation

/// 後端模擬時鐘目前狀態。
/// 日期刻意保留為 YYYY-MM-DD 字串，避免純日期經過時區轉換後偏移一天。
struct SimDateStatus: Codable, Equatable {
    let overridden: Bool
    let effectiveToday: String
    let simulatedTradeDate: String
    let resolvedDataDate: String?
    let dataAvailable: Bool
}

struct SimDateUpdateBody: Encodable {
    let date: String
}
