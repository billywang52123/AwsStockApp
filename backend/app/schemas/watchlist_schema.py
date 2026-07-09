"""觀察清單(spec 05 · 11a–11g)schemas。"""
from typing import List, Optional
from pydantic import BaseModel, ConfigDict, Field

# NaN 進到回應時直接 500,而不是被序列化成 null 害 iOS 解碼失敗
_NO_NAN = ConfigDict(allow_inf_nan=False)


# ── 11a / 11b · 清單本體 ─────────────────────────────────────

class WatchlistCreate(BaseModel):
    name: str = Field(..., min_length=1, max_length=30)
    color: Optional[str] = None


class WatchlistSummary(BaseModel):
    model_config = _NO_NAN

    id: str
    name: str
    color: Optional[str] = None
    stock_count: int


class WatchlistIndexRead(BaseModel):
    """11a 清單切換選單:持股檔數 + 全部觀察清單。"""
    holding_count: int
    watchlists: List[WatchlistSummary]


# ── 11c · 觀察清單頁 ─────────────────────────────────────────

class WatchStockRead(BaseModel):
    model_config = _NO_NAN

    symbol: str
    name: str
    industry: str
    close_price: Optional[float] = None
    change_percent: float
    ai_score: int          # 0–100,AI 評分 pill
    outlook: str           # bullish / neutral / caution
    headline: str          # 一句話理由(11f 用,11c 可忽略)


class WatchlistDetailRead(BaseModel):
    model_config = _NO_NAN

    id: str
    name: str
    color: Optional[str] = None
    stock_count: int
    average_score: int
    bullish_count: int
    neutral_count: int
    caution_count: int
    items: List[WatchStockRead]


class WatchItemAdd(BaseModel):
    symbol: str = Field(..., min_length=1)


# ── 11d · 轉入庫存 ───────────────────────────────────────────

class ConvertRequest(BaseModel):
    shares: int = Field(..., gt=0)          # 總股數(張數×1000 + 零股,由前端加總)
    price: Optional[float] = None           # 買進均價,選填


class ConvertResult(BaseModel):
    model_config = _NO_NAN

    symbol: str
    name: str
    shares: int
    watchlist_name: str     # 移出的清單名(11d 提示盒)
    total_shares: int       # 轉入後該檔總股數
    avg_price: Optional[float] = None


# ── 11e · 觀察清單分析 ───────────────────────────────────────

class WatchExposureSegment(BaseModel):
    model_config = _NO_NAN

    industry: str
    percent: float


class OverlapNotice(BaseModel):
    """與庫存重疊提醒卡(amber 警示卡,樣式同 8c)。"""
    title: str
    body: str
    highlight: str
    plain_talk: str


class WatchlistAnalysisRead(BaseModel):
    model_config = _NO_NAN

    watch_count: int
    average_score: int
    trend_note: str                          # 分數卡副行(清單今日平均漲跌)
    bullish_count: int
    neutral_count: int
    caution_count: int
    exposure: List[WatchExposureSegment]     # 清單產業分布(以檔數計)
    exposure_note: str
    overlap_notice: Optional[OverlapNotice] = None


# ── 11f · 觀點分頁 ───────────────────────────────────────────

class WatchInsightItem(BaseModel):
    model_config = _NO_NAN

    symbol: str
    name: str
    industry: str
    watchlist_name: str     # 取代權重的 subtitle(觀察股無權重概念)
    ai_score: int
    outlook: str
    headline: str


class WatchInsightListRead(BaseModel):
    bullish_count: int
    neutral_count: int
    caution_count: int
    items: List[WatchInsightItem]


# ── 11g · 推薦星標 ───────────────────────────────────────────

class RecommendedStockRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    symbol: str
    name: str
    market: str = "TW"
    industry: Optional[str] = None
    in_watchlist: bool = False
    watchlist_id: Optional[str] = None
    watchlist_name: Optional[str] = None
