import Foundation

// MARK: - 隱私儀表板(spec 05 · 10a)

/// 我們實際持有的資料逐類筆數 —— 儀表板即時顯示、刪除後逐項回報
struct PrivacySummary: Codable, Hashable {
    let holdings: Int
    let activities: Int
    let cardResults: Int
    let achievements: Int
    let reminderSettings: Int

    static let zero = PrivacySummary(
        holdings: 0, activities: 0, cardResults: 0, achievements: 0, reminderSettings: 0)
}

struct DeleteAllResult: Codable {
    let deleted: PrivacySummary
}
