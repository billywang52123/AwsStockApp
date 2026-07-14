import SwiftUI
import Testing
@testable import StockMoodApp

@MainActor
struct PackShareTests {
    private let content = ShareCardContent(
        kind: .fact,
        title: "台積電",
        subtitle: "2330",
        primaryValue: "1,550.00",
        summary: "收盤創近期新高 · 外資持股 72.76%",
        source: "CMoney",
        dataDate: "2025-12-31",
        flashLabel: "閃卡 · 數據事件",
        personalValue: "我的庫存市值 532.7萬"
    )

    @Test
    func shareCardRendersAt1080By1350Pixels() throws {
        let renderer = ImageRenderer(
            content: ShareCardImage(
                content: content,
                hidesHoldingAmount: true,
                includesSource: true
            )
        )
        renderer.scale = 3
        renderer.isOpaque = true

        let image = try #require(renderer.uiImage)
        let cgImage = try #require(image.cgImage)

        #expect(cgImage.width == 1080)
        #expect(cgImage.height == 1350)
    }

    @Test
    func shareTextKeepsDisclaimerAndAvoidsTradingLanguage() {
        #expect(content.shareText.contains("非投資建議"))
        #expect(content.shareText.contains("資料截至 2025-12-31"))
        #expect(!content.shareText.contains("建議買進"))
        #expect(!content.shareText.contains("建議賣出"))
    }
}
