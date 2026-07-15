# 股感安心卡 · iOS 切版交付包

> 視覺方向:**A 暖陽米杏**(定案)· Light Mode MVP · 全繁體中文
> 基準機型 iPhone 16 Pro(402 × 874 pt)· 單位一律 **pt**

## 包內容

| 路徑 | 內容 |
|---|---|
| `specs/00-通用規格.md` | 佈局網格、安全區、字級、色彩 tokens、共用元件、共用動畫 |
| `specs/01-庫存分析-切版規格.md` | 8a 總覽 / 8b 持股明細 / 8c 風險提醒(逐元件 redline) |
| `specs/02-個股AI觀點-切版規格.md` | 8d 觀點總覽 / 8e 觀點詳情 / **17a 統一個股詳情頁(第十五輪整併,三入口→一頁,取代 8e)** |
| `specs/03-動畫規格.md` | 庫存分析與個股觀點全部進場/互動動畫 |
| `specs/04-持股異動與多券商合併-切版規格.md` | 9a 更新入口 / 9b 加碼 / 9c 賣出 / 9d 匯入合併 / 9e 券商分帳(含均價計算與合併規則、動畫) |
| `specs/05-觀察清單-切版規格.md` | 11a 清單切換 / 11b 新增清單 / 11c 觀察清單頁 / 11d 轉入庫存 / 11e 觀察清單分析 / 11f 觀點分頁 / 11g 推薦星標 |
| `specs/06-每日抽卡包與AI信任系統-切版規格.md` | 15a 今日卡包入口 / 15b–15e 開包動畫 4 關鍵幀 / 15f 事實卡(閃卡)/ 15g 推論卡(推理鏈)/ 15h 社群卡 / 15i 出處 chip sheet / 15j 卡包架 / 15k 週末體檢 / 15L 分享 sheet / 15m 貼文預覽 |
| `specs/07-投資風格與投資習慣-切版規格.md` | 16a 風格問卷 / 16b 風格結果(四維度光譜)/ 16c 風格 → GPT Prompt 對應 / 16d 持股投資習慣(自動推算)/ 16e 風格轉變(重算+時間軸)/ **Onboarding 改版 18a–18c(風格測驗取代情境選擇,可跳過)** |
| `specs/06...`附註 | 分享 `ShareCardSheet` / `ShareCardImage`(1080×1350),隱私切換 + 出處浮水印,只帶公開數據 | 15i 出處 chip sheet / 15j 卡包架 / 15k 週末體檢 |
| `tokens/DesignTokens.json` | 全部色彩/圓角/陰影/字級 tokens(可轉 Asset Catalog,含觀察清單、每日抽卡包信任系統專屬色) |
| `AppIcon.appiconset/` | 定案 App Icon 全套切版,直接拖入 Xcode Assets |

## 對照設計稿

畫面設計稿在專案根目錄 `股感安心卡 設計畫布.dc.html`:
- 第十六輪(Onboarding 改版):`18a` 新 Onboarding 第 1 步 = 風格測驗(可跳過)· `18b` 跳過後首頁提醒 · `18c` 設定補測入口(原 1a-03 情境選擇已淘汰)
- 第十五輪:`17a` 統一個股詳情頁(白話翻譯器 + AI 觀點合併)· `17b` 入口整理規格
- 第十四輪:`16a` 投資風格問卷 · `16b` 投資風格結果 · `16c` 風格 → Prompt 規格 · `16d` 持股投資習慣 · `16e` 風格轉變
- 第十三輪:`15a` 今日卡包入口 · `15b–15e` 開包動畫 4 關鍵幀 · `15f` 事實卡(閃卡)· `15g` 推論卡(推理鏈)· `15h` 社群卡 · `15i` 出處 chip sheet · `15j` 卡包架 · `15k` 週末體檢
- 第九輪:`11a` 清單切換 · `11b` 新增觀察清單 · `11c` 觀察清單頁 · `11d` 轉入庫存 · `11e` 觀察清單分析 · `11f` 觀點分頁 · `11g` 推薦星標
- 第七輪:`9a` 更新持股入口 · `9b` 加碼買進 · `9c` 賣出 · `9d` 匯入合併決策 · `9e` 券商分帳 · `9f` 合併邏輯規格
- 第六輪:`8a` 庫存分析總覽 · `8b` 持股明細 · `8c` 風險提醒 · `8d` 個股 AI 觀點總覽 · `8e` 個股觀點詳情

## 建議元件命名(SwiftUI)

- `PortfolioSummaryCard` — 8a 紫色漸層總市值卡
- `ScoreTile` — 風險分數 / 焦慮溫度小卡
- `ExposureBar` — 產業曝險堆疊 bar + 圖例
- `HoldingRow` — 8b 持股列(含權重 bar)
- `RiskNoticeCard` — 8c 風險提醒卡(rose / amber 兩色系)
- `OutlookBadge` — 看好 / 中性 / 短線留意 pill
- `SentimentMeter` — 8e 多空溫度計
- `NewsSignalCard` — 新聞訊號卡
- `PlainSummaryBlock` — 白話總結盒(沿用既有 `ExplanationBlock` 樣式)
- `UpdateIntentSheet` — 9a 更新持股意圖選擇 bottom sheet
- `TradeInputCard` — 9b/9c 股數・價格輸入卡(含快選 chips)
- `MergePreviewCard` — 9b 攤平預覽紫卡 / 9e 合併持股卡
- `RealizedPnLBox` — 9c 已實現損益盒
- `ImportMergeRow` — 9d 重複持股合併卡(算式盒 + 三段選擇)
- `MergeChoiceSegments` — 9d 分帳加總/取代/略過 三段選擇
- `BrokerLotRow` — 9e 券商分帳列
- `ActivityLogRow` — 9e 最近異動紀錄列
- `ListSwitcher` — 11a 持股頁左上角清單切換下拉選單
- `CreateWatchlistSheet` — 11b 新增觀察清單 sheet
- `WatchlistHomeView` / `WatchlistRow` — 11c 觀察清單頁與列
- `ConvertToHoldingSheet` — 11d 觀察轉庫存(張數/零股 stepper)
- `WatchlistAnalysisView` — 11e 分析頁觀察清單分頁(含庫存重疊提醒)
- `OutlookTabView` — 11f 個股 AI 觀點持股/觀察分頁(第十五輪起降級為列表,點列進 `StockDetailView`)
- `StockDetailView` — 17a 統一個股詳情頁(取代 8e;三入口共用)
- `TodayStatusCard` / `AIOutlookCard` / `SignalRow` — 17a 上半「今天怎麼了」卡 / 下半 AI 觀點卡 / 卡內訊號列
- `TodayPackEntryView` / `PackCoverCard` — 15a 今日卡包入口與封面卡
- `FactCard` / `InferenceCard` / `CommunityCard` — 15f/15g/15h 三張核心卡(事實 / AI 推論 / 社群)
- `CardBackFace` — 15e 卡背面(卡名 + 序號 + 翻牌動畫)
- `SourceChip` / `SourceChipSheet` — 出處 chip 元件與其 bottom sheet(信任系統原子元件)
- `ReasoningStep` — 15g 推理鏈逐步展開列
- `ExpandableStockRow` — 15f 事實卡內個股明細展開列
- `PackShelfView` / `CardCollectionGrid` — 15j 卡包架與歷史卡片圖鑑
- `HonestyScoreCard` / `ReconciliationRow` — 15k AI 本週誠實度卡與對帳列
- `ShareCardSheet` — 15L 分享 bottom sheet(卡樣式預覽 + 隱私切換 + 去向列)
- `ShareCardImage` — 15m 分享卡圖(1080×1350,TCG 質感 + 出處浮水印 + 免責)
- `StyleQuizView` / `QuizOptionCard` — 16a 投資風格問卷與選項卡(18a onboarding 首步共用)
- `HomeStyleNudgeCard` — 18b 跳過測驗後的首頁補測提醒卡(可關閉,7 天冷卻)
- `SettingsPersonalizationSection` — 18c 設定「個人化」分組(風格 / 習慣兩列 + 未測金色 chip)
- `StyleResultView` / `StyleHeroCard` / `StyleAxisCard` / `TonerPreviewCard` — 16b 風格結果(大卡 + 四維度光譜 + AI 口吻預覽)
- `InvestHabitView` / `HabitTag` / `HabitStatCard` / `HabitConsistencyCard` — 16d 持股投資習慣(自動推算)
- `StyleShiftView` / `ShiftCompareCard` / `StyleTimelineCard` / `ShiftAdviceCard` — 16e 風格轉變

## 三條鐵則(全 App 通用)

1. 漲跌色遵守台股慣例:**漲/看好 = 紅系、跌/留意 = 綠系**,一律用降飽和色(見 tokens),不用高飽和紅綠。
2. 數字一律 `monospacedDigit`;中文行高 ≥ 1.6;字級全部掛 Dynamic Type。
3. 語氣安撫優先:不出現「買/賣/加碼」;每個解釋頁尾掛 `DisclaimerBlock`。

## AI 信任系統五大機制(第十三輪起,貫穿全 App)

1. **出處 chip**:所有 AI 結論句尾掛可點小標籤,點開顯示欄位/原始值/算法/資料日期 + 「這個數字你在券商 App 也查得到」
2. **推理鏈展開**:推論卡點開後逐步推理,每步是數字不是形容詞,每步附出處 chip
3. **社群溫度計**:僅顯示相對自身歷史基準的變化,不顯示絕對多空比;固定附註「社群情緒 ≠ 買賣訊號」
4. **週末體檢誠實度**:每週對帳上週 AI 說過的話,說中沒說中都照實呈現,不用紅色標示「說錯」
5. **邊界揭露**:全頁 footer 固定揭露文案 + 資料日期;全 App 禁止目標價、預測漲跌、「建議買進/賣出」字眼;閃卡觸發條件必須是寫死的數據事件,絕不能是 AI 主觀判斷

詳見 `specs/06-每日抽卡包與AI信任系統-切版規格.md`。

## 投資風格四型與 Prompt 邊界(第十四輪起)

問卷把使用者分為四型(穩健守成 `steadyKeeper` / 存股安心 `dividendCalm` / 波段嘗試 `swingTrier` / 積極衝刺 `aggressiveRunner`),並落到四維度分數(風險承受 / 持有期間 / 決策依據 / 波動反應)。

- **風格只改語氣,不改事實**:分型 + 維度 + 習慣標籤注入 GPT system prompt 的 `{tone_rules}`,只影響語氣、重點排序與資訊密度;四型看到的同一事件,**數據、資料日期必須完全相同**。
- **習慣免填寫**:16d 由持股與更新紀錄推算(產業集中度 / 平均持有 / 調整頻率 / 單次金額),同時回灌風格重算。
- **可追蹤轉變**:使用者更新持股 → 重算風格 → 16e 顯示「原風格 → 新風格」+ 維度變化 + 半年時間軸;風格分類不評價使用者(「沒有好壞」),維度箭頭用中性 amber,不套漲跌紅綠。
- **重算生效點**:新分型與習慣標籤於下一次生成生效,不回溯改寫歷史卡。

詳見 `specs/07-投資風格與投資習慣-切版規格.md`。

## 個股入口整併(第十五輪起,重要)

過去一檔股票有三個入口、兩種詳情版型,說法重疊使用者困惑:①持股列表點入的「白話狀態翻譯器」②庫存分析內文點入的「8e 個股觀點詳情」③個股觀點 tab(11f)點入的同款內容。

整併結論:**一檔股票只有一頁詳情 `StockDetailView`(17a),三個入口皆深連結進入同一頁**(單一 route `/stock/:id`,返回鍵回來源頁)。

- **白話狀態翻譯器** → 併入 17a 上半部「今天怎麼了?」區塊,不再是獨立頁。
- **8e 個股觀點詳情退役** → 內容併入 17a 下半部「AI 怎麼看接下來?」;庫存分析內文不再有第二種詳情版型。
- **個股觀點 tab(11f)保留但降級為列表** — 價值是「一次掃過全部持股+觀察」,點任一列進 17a,自身不放詳情內容。
- **同頁分區、文字不合併** — 今日狀態講「今天發生什麼」、AI 觀點講「近 7 日怎麼看」,時間軸不同,上下排列一次讀完。
- 焦慮影響 chip 只在「從持股列表進入」時於標題列顯示(觀察股不計焦慮分數)。

詳見 `specs/02-個股AI觀點-切版規格.md` 末段「## 17a · 統一個股詳情頁」。

## 觀察清單與持股的資料邊界(重要)

觀察清單(Watchlist)是「還沒買、先追蹤」的名單,與「持股」(Holding)在資料層與 UI 層都必須嚴格分離:

- 觀察清單股票**不計入**市值、損益、焦慮分數、產業曝險計算
- 分析頁(8a-8c ↔ 11e)與個股 AI 觀點頁(8d-8e ↔ 11f)一律用 segmented control 分頁,不合併列表
- 唯一的橋樑是 11d「轉入庫存」——需輸入張數/零股與選填均價,轉入後才開始計入上述所有計算
- 推薦卡(11g)若已存在某觀察清單,疊加星形徽章 + 狀態 pill,說明其「在觀察清單」而非「已持有」,避免語意混淆
