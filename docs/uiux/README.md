# 股感安心卡 · iOS 切版交付包

> 視覺方向:**A 暖陽米杏**(定案)· Light Mode MVP · 全繁體中文
> 基準機型 iPhone 16 Pro(402 × 874 pt)· 單位一律 **pt**

## 包內容

| 路徑 | 內容 |
|---|---|
| `specs/00-通用規格.md` | 佈局網格、安全區、字級、色彩 tokens、共用元件、共用動畫 |
| `specs/01-庫存分析-切版規格.md` | 8a 總覽 / 8b 持股明細 / 8c 風險提醒(逐元件 redline) |
| `specs/02-個股AI觀點-切版規格.md` | 8d 觀點總覽 / 8e 觀點詳情(多空溫度計 + 新聞訊號) |
| `specs/03-動畫規格.md` | 庫存分析與個股觀點全部進場/互動動畫 |
| `specs/04-持股異動與多券商合併-切版規格.md` | 9a 更新入口 / 9b 加碼 / 9c 賣出 / 9d 匯入合併 / 9e 券商分帳(含均價計算與合併規則、動畫) |
| `specs/05-隱私與安心-切版規格.md` | 10a 隱私儀表板 / 10b 資料存在哪裡 / 10c 敏感畫面防護(金額模糊・背景遮罩・Face ID)/ 10d 就地說明(含後端 API 對應) |
| `tokens/DesignTokens.json` | 全部色彩/圓角/陰影/字級 tokens(可轉 Asset Catalog) |
| `AppIcon.appiconset/` | 定案 App Icon 全套切版,直接拖入 Xcode Assets |

## 對照設計稿

畫面設計稿在專案根目錄 `股感安心卡 設計畫布.dc.html`:
- 第八輪:`10a` 隱私儀表板 · `10b` 資料存在哪裡 · `10c` 敏感畫面防護 · `10d` 就地說明(畫布待補,規格以 `specs/05` 為準)
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

## 三條鐵則(全 App 通用)

1. 漲跌色遵守台股慣例:**漲/看好 = 紅系、跌/留意 = 綠系**,一律用降飽和色(見 tokens),不用高飽和紅綠。
2. 數字一律 `monospacedDigit`;中文行高 ≥ 1.6;字級全部掛 Dynamic Type。
3. 語氣安撫優先:不出現「買/賣/加碼」;每個解釋頁尾掛 `DisclaimerBlock`。
