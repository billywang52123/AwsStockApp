import Foundation
import SwiftUI
import Combine

// MARK: - 每日御神籤
// 12a 入口 → 12b 搖籤 → 籤支彈出+光/煙從籤旁長出(revealing)
// → 13a/13b 綜合籤等整頁儀式(levelReveal)→ 12c 籤詩(result)
@MainActor
class FortuneViewModel: ObservableObject {
    enum Phase {
        case loading      // 開頁查今日狀態
        case entry        // 12a 搖籤入口(籤筒待機微晃)
        case shaking      // 12b 搖籤動畫
        case revealing    // 籤支彈出,金光/黑煙從籤旁慢慢長出、籠罩畫面
        case levelReveal  // 13a/13b 綜合籤等(金光爆閃 / 濃煙),CTA 看今日籤詩
        case result       // 12c 籤詩結果
    }

    @Published var phase: Phase = .loading
    @Published var fortune: FortuneResult?
    @Published var hasError = false
    @Published var errorMessage = ""

    private let container: DependencyContainer

    init(container: DependencyContainer? = nil) {
        self.container = container ?? .shared
    }

    /// 重看開籤儀式:回到入口再搖一次;後端每日冪等,回的是同一支籤
    func replayCeremony() {
        guard phase == .result else { return }
        withAnimation(.easeOut(duration: 0.25)) { phase = .entry }
    }

    /// 13a/13b CTA「看今日籤詩」→ 進籤詩
    func proceedToResult() {
        guard phase == .levelReveal else { return }
        withAnimation(.easeOut(duration: 0.45)) { phase = .result }
    }

    /// 開頁:今天抽過直接進籤詩(不重播儀式),沒抽過進入口
    func loadToday() async {
        guard phase == .loading else { return }
        do {
            fortune = try await container.fortuneService.getTodayFortune()
            phase = fortune == nil ? .entry : .result
        } catch {
            hasError = true
            errorMessage = error.localizedDescription
            phase = .entry
            print("Load today fortune failed: \(error)")
        }
    }

    /// 12b 搖籤:動畫約 2.4s,期間向後端求籤;兩者都完成才彈籤支
    func shakeAndDraw() async {
        guard phase == .entry else { return }
        hasError = false
        phase = .shaking

        async let minimumShake: Void = Task.sleep(for: .seconds(2.4))
        do {
            let result = try await container.fortuneService.drawFortune()
            try? await minimumShake
            fortune = result
            HapticManager.shared.triggerNotification(type: .success)

            // 籤支彈出 → 光/煙從籤旁長出籠罩(約 1.8s)
            withAnimation(.spring(response: 0.55, dampingFraction: 0.65)) { phase = .revealing }
            try? await Task.sleep(for: .seconds(1.8))

            // 籠罩完成 → 13a/13b 綜合籤等整頁儀式(等使用者點 CTA)
            withAnimation(.easeInOut(duration: 0.6)) { phase = .levelReveal }
        } catch {
            try? await minimumShake
            hasError = true
            errorMessage = error.localizedDescription
            phase = .entry
            print("Draw fortune failed: \(error)")
        }
    }
}
