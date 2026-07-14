"""每日抽卡包 + AI 信任系統(spec 06 · 15a–15k)schemas。

信任系統核心:所有 AI 結論句尾掛出處 chip(欄位/原始值/算法/資料日期/來源),
推理鏈每步是數字不是形容詞;閃卡觸發條件必須是寫死的數據事件。"""
from typing import List, Optional
from pydantic import BaseModel, ConfigDict

_NO_NAN = ConfigDict(allow_inf_nan=False)


class SourceChip(BaseModel):
    """出處 chip(15i):點開 bottom sheet 顯示的資料出處明細。"""
    model_config = _NO_NAN

    label: str          # chip 顯示文字,如「📊 收盤行情」
    field: str          # 使用的欄位
    raw_value: str      # 原始數值
    formula: str        # 計算方式
    data_date: str      # 資料日期
    source: str         # 資料來源


class FactRow(BaseModel):
    """事實卡個股展開列中的一行數據。"""
    model_config = _NO_NAN

    label: str
    value: str
    chip: Optional[SourceChip] = None


class FactStock(BaseModel):
    """事實卡個股明細(15f ExpandableStockRow)。"""
    model_config = _NO_NAN

    symbol: str
    name: str
    change_percent: float
    rows: List[FactRow]
    expanded_default: bool = False


class Flashcard(BaseModel):
    """閃卡觸發(15f):必須是寫死的數據事件,絕不能是 AI 主觀判斷。"""
    model_config = _NO_NAN

    event_text: str
    chip: SourceChip


class FactCardData(BaseModel):
    model_config = _NO_NAN

    total_value_text: str        # 「532.7萬」
    total_change_percent: float  # 今日加權漲跌
    total_chip: SourceChip
    stocks: List[FactStock]
    footnote: str                # 「以上都是收盤後的客觀數據…」
    flashcard: Optional[Flashcard] = None


class GlossaryTerm(BaseModel):
    """名詞小卡(15g 虛線術語)。"""
    term: str
    definition: str


class ReasoningStep(BaseModel):
    """推理鏈步驟(15g):每步是數字組合,非形容詞。"""
    model_config = _NO_NAN

    number: int
    text: str
    chip: Optional[SourceChip] = None
    glossary: Optional[GlossaryTerm] = None   # 第 3 步行為財務學說明用「📖 名詞小卡」


class InferenceCardData(BaseModel):
    model_config = _NO_NAN

    conclusion: str
    terms: List[GlossaryTerm] = []            # 結論句中可點開的虛線術語
    steps: List[ReasoningStep]
    caveat: str                               # 「這是 AI 依上列數字做的推論,可能有錯…」


class CompanionCardData(BaseModel):
    model_config = _NO_NAN

    text: str
    signature: str      # 「—— 陪你看盤的 AI」
    day_count: int      # Day N(累計開包天數)


class WhyToday(BaseModel):
    """15a「今天為什麼值得看」卡。"""
    model_config = _NO_NAN

    text: str
    chips: List[SourceChip]


class DailyPackRead(BaseModel):
    model_config = _NO_NAN

    date_text: str               # 「2025/12/31 · 週三」
    data_date: str               # footer 揭露用資料日期
    holdings_count: int
    total_value_text: str
    why_today: WhyToday
    fact: FactCardData
    inference: InferenceCardData
    companion: CompanionCardData
    opened: bool                 # 今日已看過開包動畫


# ── 15j 卡包架 ─────────────────────────────────────────────

class ShelfPack(BaseModel):
    model_config = _NO_NAN

    symbol: str
    name: str
    industry: str
    subtitle: str                # 「收盤 1,105 · +2.35%」
    has_new_insight: bool
    insight_note: Optional[str] = None


class CollectionCard(BaseModel):
    """歷史卡片圖鑑小卡。kind: fact / inference / companion / flash"""
    kind: str
    date_text: str


class PackShelfRead(BaseModel):
    model_config = _NO_NAN

    packs: List[ShelfPack]
    collected_count: int
    recent_cards: List[CollectionCard]
    more_count: int


# ── 15k 週末體檢 ───────────────────────────────────────────

class ReconciliationRow(BaseModel):
    """對帳列:上週說法 → 應驗(met)/未發生(miss),照實呈現。"""
    model_config = _NO_NAN

    statement: str
    outcome: str        # met / miss
    note: str
    chip: Optional[SourceChip] = None


class CheckupTile(BaseModel):
    model_config = _NO_NAN

    label: str
    value: str
    note: str


class WeeklyCheckupRead(BaseModel):
    model_config = _NO_NAN

    week_label: str              # 「2025 年 · 第 52 週(12/27–12/31)」
    met_count: int
    total_count: int
    rows: List[ReconciliationRow]
    tiles: List[CheckupTile]
    special_pack_note: str       # 本週特別卡包 banner 副標
