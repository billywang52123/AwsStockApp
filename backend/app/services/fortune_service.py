"""每日御神籤服務(spec 第十輪 12a–12d + 第十一輪 13a–13d)。

籤等計算全部規則式(可測試、可解釋):
- 每檔持股依當日漲跌對映六級籤等(紅偏吉 / 綠偏凶,呼應台股漲跌色)
- 綜合籤等 = 各持股籤等依權重加權
「說明 / 注意事項」文字優先由 OpenAI 生成,離線時走規則式 fallback。
每人每天一支,存檔後全天一致;語氣安撫優先,不出現操作字眼。
"""
import json
import random
from datetime import date
from typing import List, Optional

from sqlalchemy import select, and_
from sqlalchemy.orm import Session

from app.models.fortune import FortuneResultModel
from app.services.services import get_live_market_change, run_async
from app.services.portfolio_analysis_service import _load_holdings, _Holding

# 六級籤等(數值越大越吉)
LEVELS = ["大凶", "凶", "小凶", "小吉", "吉", "大吉"]

LEVEL_NOTES = {
    "大吉": "大方向順風,持股多數偏多",
    "吉": "整體安穩,照原節奏就好",
    "小吉": "穩中帶光,不急不徐",
    "小凶": "短線有雜音,看懂再說",
    "凶": "今天逆風,先別做決定",
    "大凶": "波動較大,深呼吸再看",
}

# 「今天的節奏」:語氣安撫,不用「進場/出場」等操作字眼
STANCES = {
    "大吉": ("平常心", "順風的日子照原本的節奏走就好,不用加快腳步"),
    "吉": ("平常心", "整體安穩,維持原本的計畫就好"),
    "小吉": ("不急不徐", "穩中帶光,慢慢來比較快"),
    "小凶": ("偏向觀望", "先看懂發生什麼,再決定下一步"),
    "凶": ("先觀望", "今天逆風,先不做決定,也是一種決定"),
    "大凶": ("先深呼吸", "波動較大的日子,照顧情緒比盯盤更重要"),
}

_DIGITS = "零一二三四五六七八九"


def _chinese_number(n: int) -> str:
    """1–100 → 中文數字(籤詩用:十四、二十一、一百)。"""
    if n == 100:
        return "一百"
    tens, ones = divmod(n, 10)
    if tens == 0:
        return _DIGITS[ones]
    tens_part = "十" if tens == 1 else _DIGITS[tens] + "十"
    return tens_part + (_DIGITS[ones] if ones else "")


def _level_value(change: float) -> int:
    """當日漲跌 → 六級(1=大凶 … 6=大吉)。"""
    if change >= 2.5:
        return 6
    if change >= 1.0:
        return 5
    if change >= 0.0:
        return 4
    if change > -1.0:
        return 3
    if change > -2.5:
        return 2
    return 1


def _holding_comment(h: _Holding, level: str) -> str:
    if level in ("大吉", "吉"):
        return f"今日上漲 {h.change:.2f}%,{h.industry}買盤動能穩定"
    if level == "小吉":
        return "走勢平穩,跟著原本的節奏走"
    if level == "小凶":
        return "短線有點雜音,先看著就好"
    if level == "凶":
        return f"今日下跌 {abs(h.change):.2f}%,{h.industry}短線賣壓較重"
    return f"今日下跌 {abs(h.change):.2f}%,波動較大,先深呼吸"


class FortuneService:
    def __init__(self, db: Session):
        self.db = db

    # ── 查詢 ─────────────────────────────────────────────────

    def _get_today_row(self, user_id: str) -> Optional[FortuneResultModel]:
        return self.db.scalars(select(FortuneResultModel).where(and_(
            FortuneResultModel.user_id == user_id,
            FortuneResultModel.trade_date == date.today(),
        ))).first()

    def _to_dict(self, row: FortuneResultModel, already_drawn: bool) -> dict:
        return {
            "stick_number": row.stick_number,
            "stick_label": f"第{_chinese_number(row.stick_number)}籤",
            "overall_level": row.overall_level,
            "level_note": row.level_note,
            "holdings": json.loads(row.holdings_json),
            "summary": row.summary,
            "stance": row.stance,
            "stance_note": row.stance_note,
            "notices": json.loads(row.notices_json),
            "already_drawn": already_drawn,
        }

    def get_today(self, user_id: str = "demo-user") -> Optional[dict]:
        row = self._get_today_row(user_id)
        return self._to_dict(row, already_drawn=True) if row else None

    # ── 12b 抽籤(每天一支) ──────────────────────────────────

    def draw(self, user_id: str = "demo-user", force: bool = False) -> dict:
        existing = self._get_today_row(user_id)
        if existing:
            if not force:
                return self._to_dict(existing, already_drawn=True)
            # force 重抽(測試用):丟棄今日籤,依當下持股重新計算
            self.db.delete(existing)
            self.db.flush()

        holdings = _load_holdings(self.db, user_id)
        market_change = get_live_market_change(self.db)

        # 每檔持股 → 六級
        holding_entries = []
        weighted_sum = 0.0
        weight_total = 0.0
        for h in holdings:
            value = _level_value(h.change)
            level = LEVELS[value - 1]
            holding_entries.append({
                "symbol": h.symbol,
                "name": h.name,
                "level": level,
                "comment": _holding_comment(h, level),
            })
            weight = h.weight_percent if h.weight_percent > 0 else 1.0
            weighted_sum += value * weight
            weight_total += weight

        # 綜合籤等:各持股加權;無持股時給中性偏暖的小吉
        if weight_total > 0:
            avg_value = weighted_sum / weight_total
            overall = LEVELS[min(5, max(0, int(round(avg_value)) - 1))]
        else:
            overall = "小吉"

        stance, stance_note = STANCES[overall]
        avg_change = (sum(h.change for h in holdings) / len(holdings)) if holdings else 0.0
        summary, notices = self._texts(holdings, overall, avg_change, market_change)

        row = FortuneResultModel(
            user_id=user_id,
            trade_date=date.today(),
            stick_number=random.randint(1, 100),
            overall_level=overall,
            level_note=LEVEL_NOTES[overall],
            holdings_json=json.dumps(holding_entries, ensure_ascii=False),
            summary=summary,
            stance=stance,
            stance_note=stance_note,
            notices_json=json.dumps(notices, ensure_ascii=False),
        )
        self.db.add(row)
        self.db.flush()
        return self._to_dict(row, already_drawn=False)

    # ── 「說明 / 注意事項」文字 ───────────────────────────────

    def _texts(self, holdings: List[_Holding], overall: str,
               avg_change: float, market_change: float) -> tuple:
        fallback_summary, fallback_notices = self._fallback_texts(
            holdings, overall, avg_change, market_change
        )
        from app.services.openai_service import OpenAIService
        try:
            data = run_async(OpenAIService.fetch_fortune_text(
                overall_level=overall,
                avg_change=avg_change,
                market_change=market_change,
                holdings=[
                    {"name": h.name, "symbol": h.symbol, "change_percent": h.change,
                     "industry": h.industry}
                    for h in holdings
                ],
            ))
            summary = data.get("summary") or fallback_summary
            notices = data.get("notices") or fallback_notices
            return summary, notices[:3]
        except Exception:
            return fallback_summary, fallback_notices

    def _fallback_texts(self, holdings: List[_Holding], overall: str,
                        avg_change: float, market_change: float) -> tuple:
        # 說明:可能發生的事(規則式,只描述現象)
        top_industry = None
        if holdings:
            by_ind: dict = {}
            for h in holdings:
                by_ind[h.industry] = by_ind.get(h.industry, 0.0) + h.weight_percent
            top_industry = max(by_ind, key=by_ind.get)

        if not holdings:
            summary = "目前還沒有持股,市場的波動暫時與你無關;把想追蹤的股票加入清單,籤詩會更貼近你。"
        elif overall in ("大吉", "吉"):
            summary = (f"你的持股今天平均 {avg_change:+.1f}%,"
                       f"{top_industry}板塊動能穩定,整體偏安穩;順風的日子照原本的節奏就好。")
        elif overall == "小吉":
            summary = (f"你的持股今天平均 {avg_change:+.1f}%,沒有明顯的多空訊號;"
                       "市場在等待新的方向,對長期持有者是平常的一天。")
        elif overall == "小凶":
            summary = (f"你的持股今天平均 {avg_change:+.1f}%,短線有些雜音,"
                       "但幅度還在日常呼吸範圍;先看懂原因,不用急著反應。")
        else:
            summary = (f"你的持股今天平均 {avg_change:+.1f}%,波動比平常大;"
                       "這比較像市場整體在調整,不代表公司本身出了問題,先照顧好情緒。")

        # 注意事項:只用實際資料,不編造事件
        notices: List[str] = []
        if holdings:
            worst = min(holdings, key=lambda h: h.change)
            best = max(holdings, key=lambda h: h.change)
            if worst.change <= -1.5:
                notices.append(f"{worst.name} 今日 {worst.change:+.2f}%,"
                               f"{worst.industry}消息面這幾天比較敏感,波動可能延續")
            elif best.change >= 1.5:
                notices.append(f"{best.name} 今日 {best.change:+.2f}%,"
                               "上漲後短線震盪是常見的呼吸,平常心看待")
        if abs(market_change) >= 1.0:
            notices.append(f"大盤今日 {market_change:+.2f}%,整體市場情緒起伏較大,"
                           "明天開盤的波動可能放大")
        else:
            notices.append(f"大盤今日 {market_change:+.2f}%,市場在等待新的方向,"
                           "沒有需要特別緊張的訊號")
        notices.append("籤詩每天收盤後更新,情緒有起伏時,先深呼吸再看盤")
        return summary, notices[:3]
