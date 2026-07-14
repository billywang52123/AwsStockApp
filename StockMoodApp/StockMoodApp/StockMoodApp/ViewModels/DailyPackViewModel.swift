import Foundation
import SwiftUI
import Combine

// MARK: - 每日抽卡包(spec 06 · 15a–15k)
// 15a 入口 → 15b–15e 開包動畫 4 關鍵幀 → 扇形手牌 → 點卡放大(15f/g/h)左右滑切換
@MainActor
class DailyPackViewModel: ObservableObject {
    enum Phase: Equatable {
        case loading                 // 開頁查今日狀態
        case entry                   // 15a 今日卡包入口
        case opening(keyframe: Int)  // 15b–15d:KF1 撕開 / KF2 事實卡 / KF3 推論卡
        case hand                    // 15e 三張攤成扇形手牌
        case browsing(index: Int)    // 15f/g/h 單卡放大,左右滑切換
    }

    @Published var phase: Phase = .loading
    @Published var pack: DailyPack?
    @Published var hasError = false
    @Published var errorMessage = ""

    /// 15i 出處 chip bottom sheet
    @Published var activeChip: SourceChip?
    /// 15g 名詞小卡 sheet
    @Published var activeGlossary: GlossaryTerm?

    private let container: DependencyContainer
    private var autoAdvanceTask: Task<Void, Never>?

    init(container: DependencyContainer? = nil) {
        self.container = container ?? .shared
    }

    /// 開頁:載入今日卡包(後端第一次請求時產生,全天同一包)
    func loadToday() async {
        guard phase == .loading else { return }
        do {
            pack = try await container.packService.getTodayPack(force: false)
            phase = .entry
        } catch {
            hasError = true
            errorMessage = error.localizedDescription
            phase = .entry
            print("Load today pack failed: \(error)")
        }
    }

    /// CTA「開啟今日卡包」:今天已開過(或設定總是跳過/減少動態)直達手牌,否則跑 4 關鍵幀
    func openPack(reduceMotion: Bool) {
        guard let pack, phase == .entry else { return }
        hasError = false
        let skipAnimation = pack.opened
            || AppPreferenceStore.shared.alwaysSkipPackAnimation
            || reduceMotion
        if skipAnimation {
            goToHand()
        } else {
            HapticManager.shared.triggerImpact(style: .light)
            withAnimation(.easeInOut(duration: 0.35)) { phase = .opening(keyframe: 1) }
            scheduleAutoAdvance(after: 0.9)   // KF1 撕開 ~600ms 後自動進 KF2
        }
    }

    /// 全程可 tap 任一處加速:立即觸發下一關鍵幀
    func advanceKeyframe() {
        guard case .opening(let kf) = phase else { return }
        autoAdvanceTask?.cancel()
        HapticManager.shared.triggerImpact(style: .light)
        if kf >= 3 {
            goToHand()
            return
        }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.78)) {
            phase = .opening(keyframe: kf + 1)
        }
        scheduleAutoAdvance(after: 1.5)   // 點一下接下一張 · 1.5 秒後自動
    }

    /// 右上「跳過」:直達 15e 完成態,不觸發任何一段動畫
    func skipOpening() {
        autoAdvanceTask?.cancel()
        goToHand()
    }

    private func scheduleAutoAdvance(after seconds: Double) {
        autoAdvanceTask?.cancel()
        autoAdvanceTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.advanceKeyframe()
        }
    }

    /// KF4:三張攤成手牌;到這裡就算「已開包」,通知後端
    private func goToHand() {
        autoAdvanceTask?.cancel()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { phase = .hand }
        if pack?.opened == false {
            markOpenedRemotely()
        }
        // 閃卡出現時 medium haptic(僅一次)
        if pack?.fact.flashcard != nil {
            HapticManager.shared.triggerImpact(style: .medium)
        }
    }

    private func markOpenedRemotely() {
        Task { [container] in
            try? await container.packService.markOpened()
        }
        if let current = pack {
            pack = DailyPack(
                dateText: current.dateText, dataDate: current.dataDate,
                holdingsCount: current.holdingsCount, totalValueText: current.totalValueText,
                whyToday: current.whyToday, fact: current.fact,
                inference: current.inference, companion: current.companion, opened: true
            )
        }
    }

    /// 手牌點任一張 → 放大進入該卡(進入後左右滑切換)
    func browseCard(_ index: Int) {
        guard phase == .hand else { return }
        HapticManager.shared.triggerImpact(style: .light)
        withAnimation(.easeOut(duration: 0.3)) { phase = .browsing(index: index) }
    }

    /// 15f/g/h 左右滑切換(TabView 綁定用)
    var browsingIndex: Int {
        get {
            if case .browsing(let index) = phase { return index }
            return 0
        }
        set {
            guard case .browsing(let old) = phase, old != newValue else { return }
            HapticManager.shared.triggerImpact(style: .light)
            phase = .browsing(index: newValue)
        }
    }

    /// 返回列(‹ 今日卡包):回扇形手牌
    func backToHand() {
        withAnimation(.easeOut(duration: 0.3)) { phase = .hand }
    }

    /// 收起整個開包流程回入口
    func backToEntry() {
        autoAdvanceTask?.cancel()
        withAnimation(.easeInOut(duration: 0.3)) { phase = .entry }
    }
}
