import Foundation
import Combine
import SwiftUI

// MARK: - 9d 匯入合併決策(spec 04)
// 智慧預設:同券商 → 取代該分帳(最新快照);不同券商 → 分帳加總。
// 用戶不動預設也能一鍵完成。

/// 一筆待匯入的持股,與現有持股比對後的狀態
struct ImportCandidate: Identifiable {
    var id: String { symbol }
    let symbol: String
    let name: String
    let shares: Int
    let cost: Double?
    /// nil = 全新持股(無衝突,直接新加入)
    let existing: Holding?

    var isDuplicate: Bool { existing != nil }
}

@MainActor
class ImportMergeViewModel: ObservableObject {
    @Published var candidates: [ImportCandidate]
    /// 這次截圖的來源券商 — 一律由用戶主動選定後才有值。
    /// 影像辨識的券商不一定準確,所以只當建議(detectedBroker),不自動採用;
    /// 在用戶選擇前維持 nil → brokerRequired 為 true、CTA 鎖住。
    @Published var broker: String? {
        didSet { resetDefaults() }
    }
    /// 影像辨識推測的券商,僅作為 chip/選單裡的建議,不直接寫入 broker
    let detectedBroker: String?
    @Published var actions: [String: MergeAction] = [:]
    @Published var isSubmitting = false
    @Published var errorMessage: String?

    private let container: DependencyContainer

    init(scanned: [(symbol: String, name: String, shares: Int, cost: Double?)],
         detectedBroker: String?,
         holdings: [Holding],
         container: DependencyContainer? = nil) {
        self.container = container ?? .shared
        let bySymbol = Dictionary(uniqueKeysWithValues: holdings.map { ($0.symbol, $0) })
        self.candidates = scanned.map {
            ImportCandidate(symbol: $0.symbol, name: $0.name, shares: $0.shares,
                            cost: $0.cost, existing: bySymbol[$0.symbol])
        }
        self.detectedBroker = detectedBroker
        // 無條件要求用戶確認券商:辨識結果只當建議,不直接採用
        self.broker = nil
        resetDefaults()
    }

    var duplicates: [ImportCandidate] { candidates.filter(\.isDuplicate) }
    var newOnes: [ImportCandidate] { candidates.filter { !$0.isDuplicate } }

    /// 一律要求用戶主動選定券商(辨識不一定準確),才能決定「同券商取代 / 不同券商加總」
    var brokerRequired: Bool { broker == nil }

    /// 該檔現有持股中,是否已有「這次來源券商」的分帳
    func sameBrokerLot(for candidate: ImportCandidate) -> BrokerLot? {
        candidate.existing?.lots.first { $0.broker == broker }
    }

    private func defaultAction(for candidate: ImportCandidate) -> MergeAction {
        guard candidate.isDuplicate else { return .addLot }
        // 同券商同檔 → 視為最新快照,取代該分帳;不同券商 → 新分帳加總
        return sameBrokerLot(for: candidate) != nil ? .replaceBroker : .addLot
    }

    private func resetDefaults() {
        for c in candidates {
            actions[c.symbol] = defaultAction(for: c)
        }
    }

    func action(for candidate: ImportCandidate) -> MergeAction {
        actions[candidate.symbol] ?? defaultAction(for: candidate)
    }

    /// 預設邏輯的白話理由(卡片第一層說明文字)
    func defaultReason(for candidate: ImportCandidate) -> String {
        guard candidate.isDuplicate else { return "現有紀錄裡沒有這檔,會直接新加入" }
        if let lot = sameBrokerLot(for: candidate) {
            return "同一家券商,截圖視為最新庫存,幫你更新\(lot.brokerDisplayName)的分帳"
        }
        return "不同券商,幫你分帳加總,均價自動加權"
    }

    /// 三段選項:同券商與不同券商的語意不同
    func segmentOptions(for candidate: ImportCandidate) -> [(MergeAction, String)] {
        if sameBrokerLot(for: candidate) != nil {
            return [(.replaceBroker, "更新庫存"), (.mergeAdd, "改為加總"), (.skip, "略過")]
        }
        return [(.addLot, "分帳加總"), (.replaceAll, "取代全部"), (.skip, "略過")]
    }

    /// 合併後總股數(算式盒右側)
    func mergedShares(for candidate: ImportCandidate) -> Int {
        guard let existing = candidate.existing else { return candidate.shares }
        switch action(for: candidate) {
        case .addLot, .mergeAdd:
            return existing.totalShares + candidate.shares
        case .replaceBroker:
            let sameLotShares = sameBrokerLot(for: candidate)?.shares ?? 0
            return existing.totalShares - sameLotShares + candidate.shares
        case .replaceAll:
            return candidate.shares
        case .skip:
            return existing.totalShares
        }
    }

    var affectedCount: Int {
        candidates.filter { action(for: $0) != .skip }.count
    }

    /// 選了「取代全部」的檔案 → CTA 前 destructive confirm 要列出的分帳
    var replaceAllVictims: [(name: String, lots: [BrokerLot])] {
        duplicates.compactMap { c in
            guard action(for: c) == .replaceAll, let existing = c.existing else { return nil }
            return (c.name, existing.lots)
        }
    }

    var canSubmit: Bool {
        !brokerRequired && affectedCount > 0 && !isSubmitting
    }

    func submit() async -> Bool {
        guard canSubmit else { return false }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        let decisions = candidates.compactMap { c -> MergeDecision? in
            let action = action(for: c)
            guard action != .skip, c.shares > 0 else { return nil }
            return MergeDecision(symbol: c.symbol, shares: c.shares, cost: c.cost,
                                 broker: broker, action: action.rawValue)
        }
        do {
            _ = try await container.holdingService.importMerge(decisions: decisions)
            HapticManager.shared.triggerNotification(type: .success)
            return true
        } catch {
            errorMessage = error.localizedDescription
            HapticManager.shared.triggerNotification(type: .error)
            return false
        }
    }
}
