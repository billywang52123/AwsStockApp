import Foundation
import SwiftUI
import Combine

// MARK: - 庫存分析 + 個股觀點總覽(8a–8d)
@MainActor
class AnalysisViewModel: ObservableObject {
    @Published var analysis: PortfolioAnalysis?
    @Published var insights: InsightList?
    @Published var isLoading = false
    @Published var hasError = false
    @Published var errorMessage = ""

    private let container: DependencyContainer

    init(container: DependencyContainer? = nil) {
        self.container = container ?? .shared
    }

    func load() async {
        // 首次載入才顯示全頁 loading;下拉刷新時保留舊資料避免畫面閃爍
        if analysis == nil { isLoading = true }
        hasError = false
        do {
            async let analysisTask = container.analysisService.getPortfolioAnalysis()
            async let insightsTask = container.analysisService.getInsights()
            let (analysisResult, insightsResult) = try await (analysisTask, insightsTask)
            analysis = analysisResult
            insights = insightsResult
        } catch {
            hasError = true
            errorMessage = error.localizedDescription
            print("Load analysis failed: \(error)")
        }
        isLoading = false
    }
}

// MARK: - 個股觀點詳情(8e)
@MainActor
class StockInsightDetailViewModel: ObservableObject {
    @Published var detail: StockInsightDetail?
    @Published var isLoading = false
    @Published var hasError = false
    @Published var errorMessage = ""

    private let container: DependencyContainer

    init(container: DependencyContainer? = nil) {
        self.container = container ?? .shared
    }

    func load(symbol: String) async {
        isLoading = true
        hasError = false
        do {
            detail = try await container.analysisService.getInsightDetail(symbol: symbol)
        } catch {
            hasError = true
            errorMessage = error.localizedDescription
            print("Load insight detail failed: \(error)")
        }
        isLoading = false
    }
}
