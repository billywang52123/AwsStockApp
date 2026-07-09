import Foundation
import SwiftUI
import Combine

// MARK: - 每日御神籤(12a 入口 → 12b 搖籤 → 13 開籤光效 → 12c 籤詩)
@MainActor
class FortuneViewModel: ObservableObject {
    enum Phase {
        case loading      // 開頁查今日狀態
        case entry        // 12a 搖籤入口(籤筒待機微晃)
        case shaking      // 12b 搖籤動畫
        case revealing    // 13a/13b 開籤光效(籤支已彈出)
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
            phase = .revealing

            // 13:光效約 1.8s 後收斂為結果頁頂部狀態條
            try? await Task.sleep(for: .seconds(1.8))
            withAnimation(.easeOut(duration: 0.45)) { phase = .result }
        } catch {
            try? await minimumShake
            hasError = true
            errorMessage = error.localizedDescription
            phase = .entry
            print("Draw fortune failed: \(error)")
        }
    }
}
