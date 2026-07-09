import Foundation
import SwiftUI
import Combine

// MARK: - 觀察清單(spec 05 · 11a–11d)
/// 持股頁的清單切換 + 觀察清單頁資料。selectedList == nil 代表「我的持股」。
@MainActor
class WatchlistViewModel: ObservableObject {
    @Published var index: WatchlistIndex?
    @Published var selectedList: WatchlistSummary?
    @Published var detail: WatchlistDetail?
    @Published var isLoadingDetail = false
    @Published var hasError = false
    @Published var errorMessage = ""

    private let container: DependencyContainer

    init(container: DependencyContainer? = nil) {
        self.container = container ?? .shared
    }

    var holdingCount: Int { index?.holdingCount ?? 0 }
    var watchlists: [WatchlistSummary] { index?.watchlists ?? [] }

    func loadIndex() async {
        do {
            index = try await container.watchlistService.getIndex()
            // 清單被刪或改名時,同步目前選中的清單
            if let selected = selectedList {
                selectedList = index?.watchlists.first(where: { $0.id == selected.id })
            }
        } catch {
            hasError = true
            errorMessage = error.localizedDescription
            print("Load watchlist index failed: \(error)")
        }
    }

    func select(_ list: WatchlistSummary?) async {
        selectedList = list
        detail = nil
        guard let list else { return }
        await loadDetail(id: list.id)
    }

    func loadDetail(id: String) async {
        if detail == nil { isLoadingDetail = true }
        hasError = false
        do {
            detail = try await container.watchlistService.getDetail(id: id)
        } catch {
            hasError = true
            errorMessage = error.localizedDescription
            print("Load watchlist detail failed: \(error)")
        }
        isLoadingDetail = false
    }

    func refreshSelected() async {
        await loadIndex()
        if let selected = selectedList {
            await loadDetail(id: selected.id)
        }
    }

    /// 11b 建立清單後直接切換過去
    func create(name: String, color: String?) async -> Bool {
        hasError = false
        do {
            let created = try await container.watchlistService.createWatchlist(name: name, color: color)
            await loadIndex()
            await select(index?.watchlists.first(where: { $0.id == created.id }) ?? created)
            HapticManager.shared.triggerNotification(type: .success)
            return true
        } catch {
            hasError = true
            errorMessage = error.localizedDescription
            return false
        }
    }

    func addStock(symbol: String) async {
        guard let list = selectedList else { return }
        hasError = false
        do {
            _ = try await container.watchlistService.addItem(watchlistId: list.id, symbol: symbol)
            await refreshSelected()
            HapticManager.shared.triggerNotification(type: .success)
        } catch {
            hasError = true
            errorMessage = error.localizedDescription
        }
    }

    func removeStock(symbol: String) async {
        guard let list = selectedList else { return }
        do {
            try await container.watchlistService.removeItem(watchlistId: list.id, symbol: symbol)
            await refreshSelected()
        } catch {
            hasError = true
            errorMessage = error.localizedDescription
        }
    }

    /// 11d 轉入庫存:成功後該股移出清單、開始計入市值/損益
    func convert(symbol: String, shares: Int, price: Double?) async -> ConvertResult? {
        guard let list = selectedList else { return nil }
        hasError = false
        do {
            let result = try await container.watchlistService.convertToHolding(
                watchlistId: list.id, symbol: symbol, shares: shares, price: price
            )
            await refreshSelected()
            HapticManager.shared.triggerNotification(type: .success)
            return result
        } catch {
            hasError = true
            errorMessage = error.localizedDescription
            return nil
        }
    }
}
