import Foundation

extension Notification.Name {
    /// 模擬日期套用或清除後，通知仍存活的分頁重新取得日期相關資料。
    static let simDateDidChange = Notification.Name("com.stockmoodapp.simDateDidChange")

    /// 持股異動(新增/加碼/賣出/覆蓋/還原/匯入合併/分帳編輯)成功後，
    /// 通知分析、今日儀表板等頁面自動重載，不必等使用者下拉刷新。
    static let holdingsDidChange = Notification.Name("com.stockmoodapp.holdingsDidChange")

    /// 觀察清單異動(建立/刪除清單、加入/移除股票、轉持股)成功後，通知觀察清單分析重載。
    static let watchlistDidChange = Notification.Name("com.stockmoodapp.watchlistDidChange")
}
