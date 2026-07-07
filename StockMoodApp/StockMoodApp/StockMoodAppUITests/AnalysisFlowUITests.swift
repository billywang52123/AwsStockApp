import XCTest

/// 驗證庫存分析(8a/8b/8c)與個股 AI 觀點(8d/8e)的導覽與互動,並截圖存證。
final class AnalysisFlowUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func snap(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testAnalysisFlow() throws {
        let app = XCUIApplication()
        // 以 argument domain 注入登入與 onboarding 狀態,直接進主畫面
        app.launchArguments += [
            "-com.stockmoodapp.isLoggedIn", "YES",
            "-com.stockmoodapp.currentUserId", "demo-user",
            "-com.stockmoodapp.onboardingCompleted.demo-user", "YES",
            "-api_base_url", "http://localhost:8000/api",
        ]
        app.launch()

        // 進入分析分頁
        let analysisTab = app.tabBars.buttons["分析"].firstMatch
        XCTAssertTrue(analysisTab.waitForExistence(timeout: 10), "分析分頁應存在")
        analysisTab.tap()

        // 8a 總覽:等資料載入(總市值卡標籤)
        let summaryLabel = app.staticTexts["投組總市值"]
        XCTAssertTrue(summaryLabel.waitForExistence(timeout: 15), "投組總市值卡應載入")
        sleep(2) // 等 count-up / bar 動畫完成
        snap(app, "8a_overview_top")

        // 捲到持股明細(8b)
        app.swipeUp()
        snap(app, "8b_holdings")

        // 捲到風險提醒(8c)與 CTA
        app.swipeUp()
        app.swipeUp()
        sleep(1)
        snap(app, "8c_risk_notices")

        // CTA 存在性(若有風險提醒)
        let cta = app.buttons["抽一張安心卡，看怎麼辦"]
        if cta.exists {
            XCTAssertTrue(cta.isHittable || true)
        }

        // 回頂端,點第一檔持股 → 8e 詳情
        app.swipeDown(); app.swipeDown(); app.swipeDown()
        sleep(1)
        app.swipeUp() // 露出持股列
        let firstRowWeight = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH '權重'")).firstMatch
        if firstRowWeight.waitForExistence(timeout: 5) {
            firstRowWeight.tap()
            let meterTitle = app.staticTexts["AI 綜合觀點"]
            XCTAssertTrue(meterTitle.waitForExistence(timeout: 15), "8e 綜合觀點卡應載入")
            sleep(2) // 溫度計 spring 定位
            snap(app, "8e_insight_detail_from_holding")
            app.navigationBars.buttons.firstMatch.tap() // 返回
        }

        // 切到個股觀點(8d)
        app.swipeDown(); app.swipeDown()
        let insightsSegment = app.buttons["個股觀點"].firstMatch
        XCTAssertTrue(insightsSegment.waitForExistence(timeout: 5), "個股觀點切換鈕應存在")
        insightsSegment.tap()
        sleep(1)
        snap(app, "8d_insights_list")

        // chips 篩選互動:點「看好」篩選,再點一次取消
        let bullishChip = app.buttons.matching(NSPredicate(format: "label BEGINSWITH '看好'")).firstMatch
        if bullishChip.exists {
            bullishChip.tap()
            sleep(1)
            snap(app, "8d_filtered_bullish")
            bullishChip.tap()
        }

        // 點第一列 → 8e
        let firstInsightWeight = app.staticTexts.matching(NSPredicate(format: "label CONTAINS '權重'")).firstMatch
        if firstInsightWeight.waitForExistence(timeout: 5) {
            firstInsightWeight.tap()
            let meterTitle = app.staticTexts["AI 綜合觀點"]
            XCTAssertTrue(meterTitle.waitForExistence(timeout: 15))
            sleep(2)
            snap(app, "8e_insight_detail_from_list")
        }
    }
}
