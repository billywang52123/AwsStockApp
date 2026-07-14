import Foundation

extension Notification.Name {
    /// 模擬日期套用或清除後，通知仍存活的分頁重新取得日期相關資料。
    static let simDateDidChange = Notification.Name("com.stockmoodapp.simDateDidChange")
}
