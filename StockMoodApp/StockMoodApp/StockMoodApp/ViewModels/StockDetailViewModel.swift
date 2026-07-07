import Foundation
import SwiftUI
import Combine

@MainActor
class StockDetailViewModel: ObservableObject {
    let symbol: String
    let name: String
    
    @Published var dailyPrice: StockDailyPrice? = nil
    @Published var recommendations: [Stock] = []
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
        isLoading = true
        hasError = false
        do {
            dailyPrice = try await container.stockService.getDailyPrice(symbol: symbol)
            recommendations = try await container.stockService.getRecommendations(symbol: symbol)
            
            // Core rule based explanation
            let change = dailyPrice?.changePercent ?? 0.0
            if change < -2.0 {
                anxietyImpact = "高"
                explanation = "今天 \(name) 下跌了 \(String(format: "%.1f", abs(change)))%，比大盤表現偏弱。這主要是受到科技股板塊整體修正影響。新手指引：個股跟著板塊同步拉回是正常的市場降溫現象，不代表這家公司營運出問題。先靜觀其變，不用急著做任何動作。"
            } else if change < 0.0 {
                anxietyImpact = "中"
                explanation = "今天 \(name) 小幅下跌了 \(String(format: "%.1f", abs(change)))%，走勢基本與市場大盤同步。這種日常的小碎步震盪很健康。不需要過度緊張，好股票在向上行駛的過程中，也會有稍微調整節奏的時候。"
            } else {
                anxietyImpact = "低"
                explanation = "今天 \(name) 上漲了 \(String(format: "%.1f", change))%，給持股情緒帶來很好的支撐。這表明今日買盤承接力道強。不過也要記得，上漲時保持平穩心態，照原本的節奏走就好。"
            }
        } catch {
            hasError = true
            errorMessage = error.localizedDescription
            print("Load stock details failed: \(error)")
        }
        isLoading = false
    }
}
