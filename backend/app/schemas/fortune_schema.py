"""每日御神籤(spec 第十輪 12a–12d)schemas。"""
from typing import List
from pydantic import BaseModel, ConfigDict

_NO_NAN = ConfigDict(allow_inf_nan=False)


class FortuneHolding(BaseModel):
    """「持股與狀態」欄:每檔對應六級籤等 + 一句話。"""
    model_config = _NO_NAN

    symbol: str
    name: str
    level: str          # 大吉/吉/小吉/小凶/凶/大凶
    comment: str


class FortuneRead(BaseModel):
    model_config = _NO_NAN

    stick_number: int          # 1–100
    stick_label: str           # 「第十四籤」
    overall_level: str         # 綜合籤等(各持股加權)
    level_note: str            # 籤等一句話(12d 語氣)
    holdings: List[FortuneHolding]
    summary: str               # 「說明」:可能發生的事
    stance: str                # 今天的節奏(偏向觀望 / 平常心…)
    stance_note: str
    notices: List[str]         # 「注意事項」
    already_drawn: bool        # 今日已抽(前端顯示「明天可再抽」)
