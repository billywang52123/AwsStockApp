import Foundation
import Combine

/// 16e 風格轉變紅點狀態:收到 style_shift 推播、或載入時發現新的風格轉變快照
/// 就點亮;使用者打開 StyleShiftView 看過後熄滅。跨啟動以 UserDefaults 保存。
@MainActor
final class StyleShiftCenter: ObservableObject {
    static let shared = StyleShiftCenter()

    @Published var hasUnseenShift: Bool

    private enum Keys {
        static let hasUnseen = "styleShift.hasUnseen"
        static let lastSeenSnapshotId = "styleShift.lastSeenSnapshotId"
    }

    private init() {
        hasUnseenShift = UserDefaults.standard.bool(forKey: Keys.hasUnseen)
    }

    private var lastSeenSnapshotId: String? {
        get { UserDefaults.standard.string(forKey: Keys.lastSeenSnapshotId) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.lastSeenSnapshotId) }
    }

    /// 收到 type == "style_shift" 的遠端推播時點亮。
    func flagFromPush() {
        hasUnseenShift = true
        UserDefaults.standard.set(true, forKey: Keys.hasUnseen)
    }

    /// 載入快照歷史時同步:最新一筆若相對前一筆有風格轉變、且還沒看過,就點亮。
    /// (沒收到推播——例如未授權通知——也能靠這條路補上紅點)
    func sync(history: [HabitSnapshotRead]) {
        guard let latest = history.first, history.count > 1 else { return }
        let previous = history[1]
        guard latest.observedStyle.code != previous.observedStyle.code,
              latest.id != lastSeenSnapshotId else { return }
        hasUnseenShift = true
        UserDefaults.standard.set(true, forKey: Keys.hasUnseen)
    }

    /// StyleShiftView 載入完成 = 看過了,熄滅紅點並記住已看到哪筆。
    func markSeen(latestSnapshotId: String?) {
        if let latestSnapshotId { lastSeenSnapshotId = latestSnapshotId }
        hasUnseenShift = false
        UserDefaults.standard.set(false, forKey: Keys.hasUnseen)
    }
}
