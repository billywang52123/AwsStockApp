import Foundation
import Combine
import SwiftUI

// MARK: - 9b 加碼 / 9c 賣出 / 覆蓋 的輸入與即時預覽(spec 04)

@MainActor
class TradeUpdateViewModel: ObservableObject {
    let intent: HoldingUpdateIntent
    let holding: Holding

    @Published var sharesText = ""
    @Published var priceText = ""
    /// 9b「不記得買價?先只填股數」→ 僅更新股數模式,均價不變
    @Published var sharesOnlyMode = false
    /// 多分帳時選擇異動哪個券商帳戶;nil = 賣出時由舊到新依序扣
    @Published var selectedBroker: String?
    @Published var todayPrice: Double?

    @Published var isSubmitting = false
    @Published var errorMessage: String?
    /// 全部賣出成功後顯示 undo toast(5 秒)
    @Published var showUndoToast = false
    @Published var completedResult: TradeResult?

    private let container: DependencyContainer

    init(intent: HoldingUpdateIntent, holding: Holding, container: DependencyContainer? = nil) {
        self.intent = intent
        self.holding = holding
        self.container = container ?? .shared
        // 多分帳時預設第一個帳戶(賣出預設「全部帳戶」)
        if holding.lots.count > 1, case .buy = intent {
            self.selectedBroker = holding.lots.first?.broker
        }
    }

    // MARK: - 輸入解析

    var shares: Int { Int(sharesText.filter(\.isNumber)) ?? 0 }
    var price: Double? {
        if sharesOnlyMode { return nil }
        return Double(priceText)
    }

    var canSubmit: Bool {
        guard shares > 0, !isSubmitting else { return false }
        if case .sell = intent { return shares <= holding.totalShares }
        return true
    }

    var isSellAll: Bool {
        if case .sell = intent { return shares >= holding.totalShares && holding.totalShares > 0 }
        return false
    }

    // MARK: - 即時預覽(輸入即重算,按下確認前就看得到後果)

    var previewTotalShares: Int {
        switch intent {
        case .buy: return holding.totalShares + shares
        case .sell: return max(holding.totalShares - shares, 0)
        case .override: return shares
        }
    }

    /// 加碼攤平後均價:(舊股數×舊均價 + 新股數×買價) ÷ 總股數,捨入至 0.1
    var previewAvgPrice: Double? {
        guard case .buy = intent, let buyPrice = price, shares > 0 else { return holding.avgPrice }
        let oldShares = holding.avgPrice != nil ? holding.totalShares : 0
        let oldValue = Double(oldShares) * (holding.avgPrice ?? 0)
        let total = oldShares + shares
        guard total > 0 else { return holding.avgPrice }
        return ((oldValue + Double(shares) * buyPrice) / Double(total) * 10).rounded() / 10
    }

    var avgFormulaText: String? {
        guard case .buy = intent, let buyPrice = price, shares > 0, let oldAvg = holding.avgPrice else { return nil }
        let old = holding.totalShares
        return "已自動加權攤平:(\(old.formatted()) × \(oldAvg.trimmedString) + \(shares.formatted()) × \(buyPrice.trimmedString)) ÷ \((old + shares).formatted())"
    }

    /// 9c 已實現損益 =(賣價 − 均價)× 股數
    var previewRealizedPnl: Double? {
        guard case .sell = intent, let sellPrice = price, let avg = holding.avgPrice, shares > 0 else { return nil }
        return (sellPrice - avg) * Double(shares)
    }

    var previewRealizedPnlPercent: Double? {
        guard let sellPrice = price, let avg = holding.avgPrice, avg > 0 else { return nil }
        return (sellPrice - avg) / avg * 100
    }

    // MARK: - chips

    func applyBuyChip(_ add: Int) {
        sharesText = String(shares + add)
        HapticManager.shared.triggerSelection()
    }

    func applySellRatio(_ ratio: Double) {
        let value = ratio >= 1 ? holding.totalShares : Int((Double(holding.totalShares) * ratio).rounded())
        sharesText = String(max(value, 0))
        HapticManager.shared.triggerSelection()
    }

    // MARK: - 送出

    func loadTodayPrice() async {
        todayPrice = try? await container.stockService.getDailyPrice(symbol: holding.symbol).closePrice
    }

    /// 回傳 true = 完成、可關閉頁面(全部賣出時改由 undo toast 流程收尾)
    func submit() async -> Bool {
        guard canSubmit else { return false }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        do {
            let result: TradeResult
            switch intent {
            case .buy:
                result = try await container.holdingService.buy(
                    symbol: holding.symbol, shares: shares, price: price, broker: selectedBroker)
            case .sell:
                result = try await container.holdingService.sell(
                    symbol: holding.symbol, shares: shares, price: price, broker: selectedBroker)
            case .override:
                result = try await container.holdingService.override(
                    symbol: holding.symbol, shares: shares, broker: selectedBroker)
            }
            completedResult = result
            HapticManager.shared.triggerNotification(type: .success)
            if result.exited {
                showUndoToast = true
                return false
            }
            return true
        } catch {
            errorMessage = error.localizedDescription
            HapticManager.shared.triggerNotification(type: .error)
            return false
        }
    }

    /// undo toast「還原」:把全部賣出復原
    func undoSellAll() async -> Bool {
        do {
            let result = try await container.holdingService.restore(symbol: holding.symbol)
            completedResult = result
            showUndoToast = false
            HapticManager.shared.triggerNotification(type: .success)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}

// MARK: - 數字顯示小工具

extension Double {
    /// 整數就不帶小數,否則最多 1 位(對帳單價格常見格式)
    var trimmedString: String {
        formatted(.number.precision(.fractionLength(0...1)))
    }
}
