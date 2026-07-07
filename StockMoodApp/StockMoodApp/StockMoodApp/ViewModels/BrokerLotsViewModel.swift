import Foundation
import Combine
import SwiftUI

// MARK: - 9e 個股券商分帳(spec 04)

@MainActor
class BrokerLotsViewModel: ObservableObject {
    let symbol: String

    @Published var holding: Holding?
    @Published var activities: [HoldingActivity] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let container: DependencyContainer

    init(symbol: String, holding: Holding? = nil, container: DependencyContainer? = nil) {
        self.symbol = symbol
        self.holding = holding
        self.container = container ?? .shared
    }

    func load() async {
        isLoading = holding == nil
        errorMessage = nil
        do {
            holding = try await container.holdingService.getHolding(symbol: symbol)
            activities = try await container.holdingService.getActivities(symbol: symbol)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    /// 新增/編輯券商分帳(9e):走 import/merge 的單筆決策
    /// - 新增不同券商 → add_lot;同券商已存在 → replace_broker(視為最新數字)
    func saveLot(broker: String, shares: Int, price: Double?, isEdit: Bool) async -> Bool {
        guard shares > 0 else { return false }
        let action: MergeAction = {
            if isEdit { return .replaceBroker }
            let exists = holding?.lots.contains { $0.broker == broker } ?? false
            return exists ? .mergeAdd : .addLot
        }()
        do {
            _ = try await container.holdingService.importMerge(decisions: [
                MergeDecision(symbol: symbol, shares: shares, cost: price,
                              broker: broker, action: action.rawValue)
            ])
            HapticManager.shared.triggerNotification(type: .success)
            await load()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// 刪除分帳(destructive,二次確認由 View 處理)
    func deleteLot(_ lot: BrokerLot) async {
        do {
            try await container.holdingService.deleteLot(id: lot.id)
            HapticManager.shared.triggerImpact(style: .light)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 左滑刪除異動紀錄(買/賣會回算均價)
    func deleteActivity(at offsets: IndexSet) async {
        let targets = offsets.map { activities[$0] }
        for activity in targets {
            do {
                try await container.holdingService.deleteActivity(id: activity.id)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        await load()
    }

    // MARK: - 顯示輔助

    /// 分帳占比(占比 bar 與列色條共用的排序)
    func share(of lot: BrokerLot) -> Double {
        guard let total = holding?.totalShares, total > 0 else { return 0 }
        return Double(lot.shares) / Double(total)
    }

    static func activityDescription(_ a: HoldingActivity) -> String {
        let shares = abs(a.sharesDelta).formatted()
        let brokerPrefix = a.broker.map { "\($0) · " } ?? ""
        switch a.activityType {
        case "buy": return "\(brokerPrefix)加買 \(shares) 股" + (a.price.map { " @ \($0.trimmedString)" } ?? "")
        case "sell": return "\(brokerPrefix)賣出 \(shares) 股" + (a.price.map { " @ \($0.trimmedString)" } ?? "")
        case "override": return "覆蓋為最新庫存(\(a.sharesDelta >= 0 ? "+" : "")\(a.sharesDelta.formatted()) 股)"
        case "import": return "\(brokerPrefix)截圖匯入 \(shares) 股"
        case "exit": return "全部賣出,移至已出場"
        case "restore": return "還原持股"
        default: return a.activityType
        }
    }

    static func activityDotColor(_ a: HoldingActivity) -> Color {
        switch a.activityType {
        case "buy", "import": return AppColor.upText
        case "sell", "exit": return AppColor.downText
        default: return AppColor.inkQuaternary
        }
    }
}
