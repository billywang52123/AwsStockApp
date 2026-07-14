import Foundation
import Testing
@testable import StockMoodApp

@MainActor
struct InsightExplanationTests {
    @Test
    func signalDecodesExplanationAndProvenance() throws {
        let json = Data(#"""
        {
          "source": "價格 · 今天",
          "direction": "bearish",
          "direction_label": "→ 短線偏空",
          "text": "今日收盤下跌 1.20%",
          "explanation": "單日漲跌幅代表短線價格變化",
          "calculation": "(今收 − 昨收) ÷ 昨收 × 100 = -1.20%",
          "rule": "小於等於 -0.50% 標為短線偏空",
          "data_source": "CMoney 股市資料",
          "data_date": "2025-07-14"
        }
        """#.utf8)

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let signal = try decoder.decode(NewsSignal.self, from: json)

        #expect(signal.direction == .bearish)
        #expect(signal.calculation.contains("-1.20%"))
        #expect(signal.dataSource.contains("CMoney"))
        #expect(signal.dataDate == "2025-07-14")
    }
}
