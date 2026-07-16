import Foundation
import SwiftUI
import Combine

// MARK: - 庫存分析 + 個股觀點總覽(8a–8d)+ 觀察清單分析/觀點(11e/11f)
@MainActor
class AnalysisViewModel: ObservableObject {
    @Published var analysis: PortfolioAnalysis?
    @Published var insights: InsightList?
    @Published var isLoading = false
    @Published var hasError = false
    @Published var errorMessage = ""

    // 11e/11f 觀察清單
    @Published var watchAnalysis: WatchlistAnalysis?
    @Published var watchInsights: WatchInsightList?
    @Published var watchlists: [WatchlistSummary] = []
    @Published var watchFilterId: String? = nil   // nil = 全部清單

    private let container: DependencyContainer
    private var cancellables = Set<AnyCancellable>()

    init(container: DependencyContainer? = nil) {
        self.container = container ?? .shared
        // 持股或觀察清單異動後自動重載分析,不必等使用者下拉刷新;
        // debounce 合併短時間內的連續異動(如匯入多筆、快速加減碼)只打一次 API
        NotificationCenter.default.publisher(for: .holdingsDidChange)
            .merge(with: NotificationCenter.default.publisher(for: .watchlistDidChange))
            .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { await self?.load() }
            }
            .store(in: &cancellables)
    }

    func load() async {
        // 首次載入才顯示全頁 loading;下拉刷新時保留舊資料避免畫面閃爍
        if analysis == nil { isLoading = true }
        hasError = false
        do {
            async let analysisTask = container.analysisService.getPortfolioAnalysis()
            async let insightsTask = container.analysisService.getInsights()
            async let watchAnalysisTask = container.watchlistService.getAnalysis(watchlistId: watchFilterId)
            async let watchInsightsTask = container.watchlistService.getWatchInsights()
            async let indexTask = container.watchlistService.getIndex()
            let (analysisResult, insightsResult, watchAnalysisResult, watchInsightsResult, indexResult) =
                try await (analysisTask, insightsTask, watchAnalysisTask, watchInsightsTask, indexTask)
            analysis = analysisResult
            insights = insightsResult
            watchAnalysis = watchAnalysisResult
            watchInsights = watchInsightsResult
            watchlists = indexResult.watchlists
        } catch {
            hasError = true
            errorMessage = error.localizedDescription
            print("Load analysis failed: \(error)")
        }
        isLoading = false
    }

    /// 11e 清單篩選 chips:切換單一清單 / 全部
    func applyWatchFilter(_ id: String?) async {
        watchFilterId = id
        do {
            watchAnalysis = try await container.watchlistService.getAnalysis(watchlistId: id)
        } catch {
            print("Load watch analysis failed: \(error)")
        }
    }
}
