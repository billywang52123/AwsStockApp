import Foundation
import SwiftUI
import Combine

// MARK: - 每日抽卡包(spec 06 · 15a–15k)
// 15a 入口 → 15b 撕開動畫 → 卡疊覆蓋態(卡背朝上)→ 點擊翻牌(15f/g/h)左右滑切換
// 卡片內容一律等使用者點擊卡背翻牌才揭曉,開包動畫不先露出內容
@MainActor
class DailyPackViewModel: ObservableObject {
    enum Phase: Equatable {
        case loading                 // 開頁查今日狀態
        case entry                   // 15a 今日卡包入口
        case opening                 // 15b 撕開動畫(不露卡片內容)
        case stack                   // 15e 卡疊覆蓋態(三張卡背朝上,滑動選卡、點擊翻牌)
        case browsing(index: Int)    // 15f/g/h 完成態,左右滑切換
    }

    @Published var phase: Phase = .loading
    @Published var pack: DailyPack?
    @Published var hasError = false
    @Published var errorMessage = ""

    /// 15e 卡疊:目前在前景的卡(0 事實 / 1 推論 / 2 社群)
    @Published var stackFront: Int = 0
    /// 已翻開過的卡(翻過的直接顯示完成態;未翻的滑到時先播翻牌動畫)
    @Published var flippedKinds: Set<Int> = []

    /// 15i 出處 chip bottom sheet
    @Published var activeChip: SourceChip?
    /// 15g 名詞小卡 sheet
    @Published var activeGlossary: GlossaryTerm?

    private let container: DependencyContainer
    private var autoAdvanceTask: Task<Void, Never>?

    init(container: DependencyContainer? = nil) {
        self.container = container ?? .shared
    }

    /// 卡包架回顧模式:使用當日已存快照,不重新請求或改寫後端開封狀態。
    init(archivedPack: DailyPack, container: DependencyContainer? = nil) {
        self.container = container ?? .shared
        self.pack = archivedPack
        self.phase = .browsing(index: PackCardKind.fact.rawValue)
        self.flippedKinds = Set(PackCardKind.allCases.map(\.rawValue))
    }

    /// 開頁:載入今日卡包(後端第一次請求時產生,全天同一包)
    func loadToday() async {
        guard phase == .loading else { return }
        do {
            let shouldForce = AppPreferenceStore.shared.shouldRegeneratePackAfterSimDateChange
            pack = try await container.packService.getTodayPack(force: shouldForce)
            if shouldForce {
                AppPreferenceStore.shared.shouldRegeneratePackAfterSimDateChange = false
            }
            phase = .entry
        } catch {
            hasError = true
            errorMessage = error.localizedDescription
            phase = .entry
            print("Load today pack failed: \(error)")
        }
    }

    /// 模擬日期切換後強制重生該日期的卡包，讓使用者從未開封入口重新抽卡。
    func reloadAfterSimDateChange() async {
        autoAdvanceTask?.cancel()
        phase = .loading
        pack = nil
        stackFront = 0
        flippedKinds = []
        activeChip = nil
        activeGlossary = nil
        hasError = false
        errorMessage = ""

        do {
            pack = try await container.packService.getTodayPack(force: true)
            AppPreferenceStore.shared.shouldRegeneratePackAfterSimDateChange = false
            phase = .entry
        } catch {
            hasError = true
            errorMessage = error.localizedDescription
            phase = .entry
            print("Reload pack after simulated date change failed: \(error)")
        }
    }

    /// CTA「開啟今日卡包」:今天已開過(或設定總是跳過/減少動態)直達卡疊,
    /// 否則播撕開動畫後亮出三張卡背,等使用者自己點擊翻牌
    func openPack(reduceMotion: Bool) {
        guard let pack, phase == .entry else { return }
        hasError = false
        let skipAnimation = pack.opened
            || AppPreferenceStore.shared.alwaysSkipPackAnimation
            || reduceMotion
        if skipAnimation {
            goToStack()
        } else {
            HapticManager.shared.triggerImpact(style: .light)
            withAnimation(.easeInOut(duration: 0.35)) { phase = .opening }
            scheduleAutoAdvance(after: 1.2)   // 撕開動畫播完自動亮出卡背
        }
    }

    /// 撕開動畫中 tap 任一處加速:直接亮出卡背卡疊
    func advanceKeyframe() {
        guard phase == .opening else { return }
        autoAdvanceTask?.cancel()
        HapticManager.shared.triggerImpact(style: .light)
        goToStack()
    }

    /// 右上「跳過」:直達 15e 卡疊覆蓋態,不觸發任何一段動畫
    func skipOpening() {
        autoAdvanceTask?.cancel()
        goToStack()
    }

    private func scheduleAutoAdvance(after seconds: Double) {
        autoAdvanceTask?.cancel()
        autoAdvanceTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.advanceKeyframe()
        }
    }

    /// KF4:卡疊覆蓋態(三張卡背朝上);到這裡就算「已開包」,通知後端
    private func goToStack() {
        autoAdvanceTask?.cancel()
        stackFront = 0
        flippedKinds = []
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { phase = .stack }
        if pack?.opened == false {
            markOpenedRemotely()
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
                inference: current.inference, communityCard: current.communityCard,
                opened: true
            )
        }
    }

    /// 15e 卡疊左右滑動選卡:卡疊輪轉(+1 下一張升前景 / −1 上一張)
    func rotateStack(_ direction: Int) {
        guard phase == .stack else { return }
        HapticManager.shared.triggerImpact(style: .light)
        withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
            stackFront = ((stackFront + direction) % 3 + 3) % 3
        }
    }

    /// 點擊前景卡翻牌 → 進入該卡完成態(翻牌動畫由 view 播,播到 90° 時呼叫)
    func revealFrontCard() {
        guard phase == .stack else { return }
        flippedKinds.insert(stackFront)
        // 翻開的是閃卡:金光爆開瞬間 medium haptic(僅一次)
        if stackFront == PackCardKind.fact.rawValue, pack?.fact.flashcard != nil {
            HapticManager.shared.triggerImpact(style: .medium)
        } else {
            HapticManager.shared.triggerImpact(style: .light)
        }
        phase = .browsing(index: stackFront)
    }

    /// 15f/g/h 左右滑切換(TabView 綁定用);滑向未翻開的卡由 view 播翻牌動畫
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

    /// 完成態中標記某卡已翻開(滑到未翻卡、翻牌動畫播完時)
    func markFlipped(_ index: Int) {
        flippedKinds.insert(index)
    }

    /// 返回列(‹ 今日卡包):回卡疊覆蓋態
    func backToStack() {
        if case .browsing(let index) = phase {
            stackFront = index   // 卡疊前景停在剛剛看的那張
        }
        withAnimation(.easeOut(duration: 0.3)) { phase = .stack }
    }

    /// 收起整個開包流程回入口
    func backToEntry() {
        autoAdvanceTask?.cancel()
        withAnimation(.easeInOut(duration: 0.3)) { phase = .entry }
    }

    /// 離開抽卡分頁時收起暫存互動；保留已載入卡包及 opened 狀態，
    /// 下次回來直接顯示「今日卡包」入口與「再看今日卡包」。
    func prepareForNextVisit() {
        autoAdvanceTask?.cancel()
        activeChip = nil
        activeGlossary = nil
        stackFront = 0
        flippedKinds = []
        guard pack != nil else { return }
        phase = .entry
    }
}
