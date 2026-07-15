import Foundation
import SwiftUI
import Combine

// MARK: - 17a 統一個股詳情頁(白話翻譯器 + AI 觀點合併)
@MainActor
class StockDetailViewModel: ObservableObject {
    let symbol: String
    let name: String

    @Published var dailyPrice: StockDailyPrice? = nil
    @Published var marketChangePercent: Double? = nil
    @Published var insight: StockInsightDetail? = nil
    @Published var recommendations: [RecommendedStock] = []
    @Published var todayReasons: [String] = []
    @Published var explanation = ""
    @Published var anxietyImpact = "低"
    @Published var isLoading = false
    @Published var hasError = false
    @Published var errorMessage = ""

    @Published var aiAnalysisText: String? = nil
    @Published var isFetchingAIAnalysis = false

    private let container: DependencyContainer

    init(symbol: String, name: String, container: DependencyContainer? = nil) {
        self.symbol = symbol
        self.name = name
        self.container = container ?? .shared
    }

    func fetchAIAnalysis() async {
        isFetchingAIAnalysis = true
        hasError = false

        do {
            let res: String = try await APIClient.shared.request("/stocks/\(symbol)/ai-analysis")
            aiAnalysisText = res
        } catch {
            // Surface actual error + show offline fallback text so the sheet is still useful
            errorMessage = "AI 分析連線失敗：\(error.localizedDescription)"
            hasError = true
            aiAnalysisText = "【發生什麼】\n今天 \(name) 面臨拉回壓力，市場受升息疑慮及大宗商品波動影響，科技板塊普遍降溫。\n\n【跟你有關】\n帳面波動容易影響晚上睡眠，請記得這只是合理的市場呼吸。短期切忌盲目下單。\n\n【可以留意】\n先冷靜觀察幾天，保持閒錢投資以分散心理負擔。\n\n⚠️ 以上為離線備用內容，AI 分析連線失敗。"
        }
        isFetchingAIAnalysis = false
    }

    func loadDetails() async {
        if dailyPrice == nil { isLoading = true }
        hasError = false
        do {
            async let priceTask = container.stockService.getDailyPrice(symbol: symbol)
            async let recsTask = container.stockService.getRecommendations(symbol: symbol)
            let (price, recs) = try await (priceTask, recsTask)
            dailyPrice = price
            recommendations = recs
        } catch {
            hasError = true
            errorMessage = error.localizedDescription
            print("Load stock details failed: \(error)")
        }

        // 大盤對比與 AI 觀點各自獨立失敗:缺一不擋整頁
        marketChangePercent = try? await container.marketService.getMarketCompare().marketChangePercent
        insight = try? await container.analysisService.getInsightDetail(symbol: symbol)

        buildTodayNarrative()
        isLoading = false
    }

    // MARK: - 上半部「今天怎麼了?」原因點列 + 新手翻譯

    private func buildTodayNarrative() {
        let change = dailyPrice?.changePercent ?? 0.0
        var reasons: [String] = []

        // 原因 1:個股 vs 大盤的相對位置
        if let market = marketChangePercent {
            let relative = change - market
            if abs(relative) < 0.5 {
                reasons.append("走勢和大盤同步(大盤 \(StockFormat.signedPercent(market, digits: 1)))，屬於整體市場的呼吸")
            } else if relative > 0 {
                reasons.append("比大盤強 \(String(format: "%.1f", relative)) 個百分點，今天有自己的買盤支撐")
            } else {
                reasons.append("比大盤弱 \(String(format: "%.1f", abs(relative))) 個百分點，壓力主要來自個股本身")
            }
        } else if change < 0 {
            reasons.append("今天收 \(StockFormat.signedPercent(change, digits: 1))，屬於日常波動範圍")
        } else {
            reasons.append("今天收 \(StockFormat.signedPercent(change, digits: 1))，買盤承接力道穩定")
        }

        // 原因 2:借用 AI 觀點的第一個訊號(固定數據事件,非主觀判斷)
        if let firstSignal = insight?.signals.first {
            reasons.append(firstSignal.text)
        } else if let industry = insight?.industry {
            reasons.append("與 \(industry) 族群連動，板塊同步進退是正常現象")
        }
        todayReasons = reasons

        // 新手翻譯盒(維持原白話翻譯器規則)
        if change < -2.0 {
            anxietyImpact = "高"
            explanation = "今天 \(name) 下跌了 \(String(format: "%.1f", abs(change)))%，比平常的波動大一些。個股跟著板塊同步拉回是正常的市場降溫現象，不代表這家公司營運出問題。先靜觀其變，不用急著做任何動作。"
        } else if change < 0.0 {
            anxietyImpact = "中"
            explanation = "今天 \(name) 小幅下跌了 \(String(format: "%.1f", abs(change)))%，走勢基本與市場大盤同步。這種日常的小碎步震盪很健康，不需要過度緊張。"
        } else {
            anxietyImpact = "低"
            explanation = "今天 \(name) 上漲了 \(String(format: "%.1f", change))%，給持股情緒帶來很好的支撐。上漲時保持平穩心態，照原本的節奏走就好。"
        }
    }
}
