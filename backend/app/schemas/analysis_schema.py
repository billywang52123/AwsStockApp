from typing import List, Optional
from pydantic import BaseModel


# ── 庫存分析(8a / 8b / 8c) ─────────────────────────────────

class ExposureSegment(BaseModel):
    industry: str
    percent: float


class HoldingDetail(BaseModel):
    id: str
    symbol: str
    name: str
    industry: str
    shares: Optional[int] = None
    cost_price: Optional[float] = None
    close_price: Optional[float] = None
    market_value: float
    pnl: float
    pnl_percent: float
    weight_percent: float
    change_percent: float


class RiskNotice(BaseModel):
    severity: str          # "rose"(優先檢查) / "amber"(注意)
    badge: str             # 「優先檢查」/「注意」
    title: str
    body: str
    highlight: str         # 內文中要加粗強調的關鍵數字片段
    plain_talk: str        # 白話說:...


class PortfolioAnalysisRead(BaseModel):
    total_market_value: float
    total_cost: float
    unrealized_pnl: float
    unrealized_pnl_percent: float
    holdings_count: int
    risk_score: int
    risk_note: str
    anxiety_score: int
    anxiety_note: str
    exposure: List[ExposureSegment]
    tech_exposure_percent: float
    exposure_note: str
    holdings: List[HoldingDetail]
    risk_notices: List[RiskNotice]


# ── 個股 AI 觀點(8d / 8e) ─────────────────────────────────

class StockInsightSummary(BaseModel):
    symbol: str
    name: str
    industry: str
    weight_percent: float
    outlook: str           # bullish / neutral / caution
    outlook_score: int     # 0–100,溫度計位置
    headline: str          # 一句話理由


class InsightListRead(BaseModel):
    bullish_count: int
    neutral_count: int
    caution_count: int
    items: List[StockInsightSummary]


class NewsSignal(BaseModel):
    source: str            # 「價格 · 今天」等
    direction: str         # bullish / bearish / neutral
    direction_label: str   # 「→ 短線偏空」等
    text: str


class StockInsightDetail(BaseModel):
    symbol: str
    name: str
    industry: str
    outlook: str
    outlook_score: int
    stance_label: str      # 「短線留意 · 長線看好」
    summary: str           # 主句
    signals: List[NewsSignal]
    plain_summary: str
