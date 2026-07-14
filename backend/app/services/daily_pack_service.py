"""每日抽卡包 + AI 信任系統服務(spec 06 · 15a–15k,取代御神籤)。

設計原則(信任系統五大機制):
- 事實卡/推論卡全部規則式、以 DB 內實際數據計算,每句結論掛出處 chip
- 推理鏈每步是數字組合,不是形容詞
- 閃卡觸發條件必須是寫死的數據事件(單日 ±3%、收盤創近 60 日新高),絕不是 AI 判斷
- 陪伴卡文字優先 OpenAI 生成、離線走規則式 fallback,零買賣暗示
- 產生卡包時同步存下可對帳的 claims,週末體檢照實對帳(說錯也原樣寫出)
每人每交易日一包,存檔後全天一致。
"""
import json
from datetime import date, datetime, time, timedelta
from typing import List, Optional, Tuple
from zoneinfo import ZoneInfo

from sqlalchemy import select, and_, func
from sqlalchemy.orm import Session

from app.models.daily_pack import DailyPackModel
from app.models.stock_daily_price import StockDailyPrice
from app.services.services import get_live_market_change, run_async
from app.services.portfolio_analysis_service import _load_holdings, _Holding, TECH_INDUSTRY_KEYWORDS

TAIPEI = ZoneInfo("Asia/Taipei")

# 台股收盤資料更新時間;之前打 today 拿到的是前一交易日的包
PACK_OPEN = time(14, 30)

WEEKDAYS = ["一", "二", "三", "四", "五", "六", "日"]

DISCLOSURE_SOURCE = "台灣證交所收盤行情(經 Yahoo Finance)"


def _now_taipei() -> datetime:
    return datetime.now(TAIPEI)


def pack_trade_date(now: Optional[datetime] = None) -> date:
    """今日卡包對應的交易日:14:30 前算前一日(收盤後更新)。"""
    now = now or _now_taipei()
    if now.time() < PACK_OPEN:
        return now.date() - timedelta(days=1)
    return now.date()


def _wan_text(value: float) -> str:
    """金額 → 「532.7萬」;不足一萬顯示整數元。"""
    if value >= 10000:
        return f"{value / 10000:,.1f}萬"
    return f"{value:,.0f}"


def _date_text(d: date) -> str:
    return f"{d.year}/{d.month:02d}/{d.day:02d} · 週{WEEKDAYS[d.weekday()]}"


def _chip(label: str, field: str, raw_value: str, formula: str, data_date: date) -> dict:
    return {
        "label": label,
        "field": field,
        "raw_value": raw_value,
        "formula": formula,
        "data_date": data_date.isoformat(),
        "source": DISCLOSURE_SOURCE,
    }


class DailyPackService:
    def __init__(self, db: Session):
        self.db = db

    # ── 查詢 / 產生 ──────────────────────────────────────────

    def _get_row(self, user_id: str, trade_date: date) -> Optional[DailyPackModel]:
        return self.db.scalars(select(DailyPackModel).where(and_(
            DailyPackModel.user_id == user_id,
            DailyPackModel.trade_date == trade_date,
        ))).first()

    def get_today(self, user_id: str = "demo-user", force: bool = False) -> dict:
        """今日卡包;第一次請求時產生並存檔,之後全天回同一包。"""
        trade_date = pack_trade_date()
        row = self._get_row(user_id, trade_date)
        if row and not force:
            payload = json.loads(row.pack_json)
            payload["opened"] = bool(row.opened)
            return payload
        if row:
            # force 重生(測試用):丟棄今日包,依當下持股重算
            self.db.delete(row)
            self.db.flush()

        payload = self._build_pack(user_id, trade_date)
        row = DailyPackModel(
            user_id=user_id,
            trade_date=trade_date,
            opened=False,
            pack_json=json.dumps(payload, ensure_ascii=False),
        )
        self.db.add(row)
        self.db.flush()
        payload["opened"] = False
        return payload

    def mark_opened(self, user_id: str = "demo-user") -> bool:
        """開包動畫看完(或跳過)後標記;之後開頁直達完成態。"""
        row = self._get_row(user_id, pack_trade_date())
        if not row:
            return False
        row.opened = True
        self.db.flush()
        return True

    def _day_count(self, user_id: str) -> int:
        return int(self.db.scalar(
            select(func.count()).select_from(DailyPackModel)
            .where(DailyPackModel.user_id == user_id)
        ) or 0)

    # ── 卡包內容 ─────────────────────────────────────────────

    def _build_pack(self, user_id: str, trade_date: date) -> dict:
        holdings = _load_holdings(self.db, user_id)
        market_change = get_live_market_change(self.db)

        total_value = sum(h.market_value for h in holdings)
        total_text = _wan_text(total_value)
        # 加權漲跌(權重 = 市值占比)
        weighted_change = (
            sum(h.change * h.weight_percent for h in holdings) / 100.0
            if holdings else 0.0
        )

        fact = self._fact_card(holdings, total_value, weighted_change, trade_date)
        inference, claims = self._inference_card(
            holdings, weighted_change, market_change, trade_date
        )
        companion = self._companion_card(user_id, holdings, weighted_change, market_change)
        why_today = self._why_today(holdings, weighted_change, market_change, fact, trade_date)

        return {
            "date_text": _date_text(trade_date),
            "data_date": trade_date.isoformat(),
            "holdings_count": len(holdings),
            "total_value_text": total_text,
            "why_today": why_today,
            "fact": fact,
            "inference": inference,
            "companion": companion,
            # 內部欄位:15k 對帳用,schema 不外露
            "claims": claims,
        }

    # ── 事實卡(15f):可驗證的庫存數據 ───────────────────────

    def _fact_card(self, holdings: List[_Holding], total_value: float,
                   weighted_change: float, trade_date: date) -> dict:
        total_chip = _chip(
            "📊 庫存市值", "收盤價 × 股數(逐檔加總)",
            f"{total_value:,.0f} 元",
            "Σ(各檔最新收盤價 × 持有股數)", trade_date,
        )

        stocks = []
        ordered = sorted(holdings, key=lambda h: h.weight_percent, reverse=True)
        for i, h in enumerate(ordered):
            rows = [
                {
                    "label": "收盤價",
                    "value": f"{h.close:,.2f}" if h.close is not None else "—",
                    "chip": _chip("📊 收盤行情", f"{h.symbol} close_price",
                                  f"{h.close:,.2f}" if h.close is not None else "無資料",
                                  "當日收盤價,未經任何調整", trade_date),
                },
                {
                    "label": "今日漲跌",
                    "value": f"{h.change:+.2f}%",
                    "chip": _chip("📊 漲跌幅", f"{h.symbol} change_percent",
                                  f"{h.change:+.2f}%",
                                  "(今收 − 昨收) ÷ 昨收 × 100%", trade_date),
                },
                {
                    "label": "庫存占比",
                    "value": f"{h.weight_percent:.1f}%",
                    "chip": _chip("📊 占比", f"{h.symbol} 市值權重",
                                  f"{h.market_value:,.0f} 元",
                                  "該檔市值 ÷ 庫存總市值 × 100%", trade_date),
                },
            ]
            stocks.append({
                "symbol": h.symbol,
                "name": h.name,
                "change_percent": round(h.change, 2),
                "rows": rows,
                "expanded_default": i == 0,   # 權重最大的一檔預設展開
            })

        return {
            "total_value_text": _wan_text(total_value),
            "total_change_percent": round(weighted_change, 2),
            "total_chip": total_chip,
            "stocks": stocks,
            "footnote": "以上都是收盤後的客觀數據,你在券商 App 也查得到",
            "flashcard": self._flashcard(ordered, trade_date),
        }

    def _flashcard(self, holdings: List[_Holding], trade_date: date) -> Optional[dict]:
        """閃卡觸發:只有寫死的數據事件(±3% / 創近 60 日收盤新高)。"""
        for h in holdings:
            if abs(h.change) >= 3.0:
                direction = "上漲" if h.change > 0 else "下跌"
                return {
                    "event_text": f"{h.name} 單日{direction} {abs(h.change):.2f}%(達 ±3% 事件門檻)",
                    "chip": _chip("📊 漲跌幅", f"{h.symbol} change_percent",
                                  f"{h.change:+.2f}%",
                                  "|單日漲跌幅| ≥ 3%(寫死門檻,非 AI 判斷)", trade_date),
                }
        # 權重最高的一檔:收盤創近 60 日新高
        for h in holdings[:1]:
            if h.close is None:
                continue
            prev = self.db.scalars(
                select(StockDailyPrice.close_price)
                .where(StockDailyPrice.symbol == h.symbol)
                .order_by(StockDailyPrice.trade_date.desc())
                .limit(60)
            ).all()
            history = [p for p in prev[1:] if p is not None]
            if len(history) >= 5 and h.close >= max(history):
                return {
                    "event_text": f"{h.name} 收盤價創近 {len(history)} 個交易日新高",
                    "chip": _chip("📊 收盤行情", f"{h.symbol} close_price",
                                  f"{h.close:,.2f}",
                                  f"今日收盤 ≥ 近 {len(history)} 日收盤最大值(寫死條件)", trade_date),
                }
        return None

    # ── 推論卡(15g):每步是數字,附出處 chip ─────────────────

    def _inference_card(self, holdings: List[_Holding], weighted_change: float,
                        market_change: float, trade_date: date) -> Tuple[dict, list]:
        claims: list = []
        if not holdings:
            inference = {
                "conclusion": "目前沒有持股,市場的波動暫時與你的資產無關。",
                "terms": [],
                "steps": [{
                    "number": 1,
                    "text": "庫存檔數 0,庫存市值 0 元 —— 沒有部位,就沒有需要判斷的風險。",
                    "chip": _chip("📊 庫存", "持股檔數", "0 檔", "持股資料表逐筆計數", trade_date),
                    "glossary": None,
                }],
                "caveat": "這是 AI 依上列數字做的推論,可能有錯;但每一步用到的數字都查得到。",
            }
            return inference, claims

        tech_pct = round(sum(h.weight_percent for h in holdings if h.is_tech), 1)
        top = max(holdings, key=lambda h: h.weight_percent)
        ratio = (weighted_change / market_change) if abs(market_change) >= 0.3 else None

        # 結論句:集中度為主軸(數字可驗證)
        if tech_pct >= 60.0:
            conclusion = (f"科技類佔你庫存 {tech_pct:.1f}%,今天整體庫存"
                          f"{'跟著大盤放大波動' if ratio and abs(ratio) > 1.2 else '大致跟著大盤呼吸'}"
                          f"(庫存 {weighted_change:+.2f}% vs 大盤 {market_change:+.2f}%)。")
        else:
            conclusion = (f"你的庫存今天加權 {weighted_change:+.2f}%,大盤 {market_change:+.2f}%,"
                          f"最大部位 {top.name} 佔 {top.weight_percent:.1f}%,是今天分數的主要來源。")

        steps = [
            {
                "number": 1,
                "text": (f"{len(holdings)} 檔庫存中,科技類佔 {tech_pct:.1f}%,"
                         f"最大單一部位 {top.name} 佔 {top.weight_percent:.1f}%。"),
                "chip": _chip("📊 產業占比", "各檔市值權重 × 產業分類",
                              f"科技類 {tech_pct:.1f}%",
                              "Σ(科技類個股市值) ÷ 庫存總市值 × 100%", trade_date),
                "glossary": None,
            },
            {
                "number": 2,
                "text": (f"今日大盤 {market_change:+.2f}%,你的庫存加權 {weighted_change:+.2f}%"
                         + (f",波動倍率約 {abs(ratio):.1f} 倍。" if ratio is not None else "。")),
                "chip": _chip("📊 相對波動", "庫存加權漲跌 ÷ 大盤漲跌",
                              f"{weighted_change:+.2f}% / {market_change:+.2f}%",
                              "Σ(各檔漲跌 × 市值權重) 與 TAIEX 當日漲跌比較", trade_date),
                "glossary": None,
            },
            {
                "number": 3,
                "text": ("行為財務學的「損失趨避」:下跌 1% 帶來的不舒服,"
                         "大約是上漲 1% 帶來快樂的 2 倍——所以分數看起來大,不代表要做什麼。"),
                "chip": None,
                "glossary": {
                    "term": "損失趨避",
                    "definition": ("Kahneman 與 Tversky 的展望理論發現:同樣幅度的損失,"
                                   "心理痛感約是獲利快樂的 2 倍。知道這件事,"
                                   "可以幫你把「感覺很嚴重」和「實際數字」分開來看。"),
                },
            },
        ]

        terms = [{
            "term": "波動倍率",
            "definition": ("庫存加權漲跌 ÷ 大盤漲跌。大於 1 表示你的組合比大盤動得更大,"
                           "通常來自產業集中;它描述現況,不預測明天。"),
        }]

        # 可對帳 claims(15k):現在說的話,週末照實驗證
        if tech_pct >= 60.0:
            claims.append({
                "kind": "concentration",
                "statement": f"科技類集中度 {tech_pct:.1f}%,高於 60% 提醒線,短期內可能維持",
                "threshold": 60.0,
                "baseline": tech_pct,
                "date": trade_date.isoformat(),
            })
        vol = max(holdings, key=lambda h: abs(h.change))
        if abs(vol.change) >= 1.5:
            claims.append({
                "kind": "volatility",
                "statement": f"{vol.name} 單日 {vol.change:+.2f}%,短線波動可能延續(|漲跌| ≥ 1.5%)",
                "symbol": vol.symbol,
                "name": vol.name,
                "threshold": 1.5,
                "baseline": vol.change,
                "date": trade_date.isoformat(),
            })
        if abs(market_change) >= 1.0:
            claims.append({
                "kind": "market",
                "statement": f"大盤單日 {market_change:+.2f}%,整體市場情緒起伏可能放大(|漲跌| ≥ 1%)",
                "threshold": 1.0,
                "baseline": market_change,
                "date": trade_date.isoformat(),
            })

        inference = {
            "conclusion": conclusion,
            "terms": terms,
            "steps": steps,
            "caveat": "這是 AI 依上列數字做的推論,可能有錯;但每一步用到的數字都查得到。",
        }
        return inference, claims

    # ── 陪伴卡(15h):OpenAI 優先、規則式 fallback,零買賣暗示 ──

    def _companion_card(self, user_id: str, holdings: List[_Holding],
                        weighted_change: float, market_change: float) -> dict:
        day_count = self._day_count(user_id) + 1
        text = self._companion_fallback(holdings, weighted_change)
        from app.services.openai_service import OpenAIService
        try:
            ai_text = run_async(OpenAIService.fetch_companion_text(
                avg_change=weighted_change,
                market_change=market_change,
                holdings_count=len(holdings),
            ))
            if ai_text:
                text = ai_text
        except Exception:
            pass
        return {
            "text": text,
            "signature": "—— 陪你看盤的 AI",
            "day_count": day_count,
        }

    @staticmethod
    def _companion_fallback(holdings: List[_Holding], weighted_change: float) -> str:
        if not holdings:
            return ("今天還沒有部位,也就沒有需要掛心的波動。"
                    "把好奇的股票放進觀察清單,我們慢慢看、不急著決定。")
        if weighted_change <= -1.5:
            return ("今天的紅字看起來比較刺眼,先深呼吸。"
                    "數字會每天變,你看懂市場的能力只會累積。"
                    "波動是市場的呼吸,不是你的錯。今天照顧好情緒,就已經做得很好了。")
        if weighted_change < 0:
            return ("小幅回落的日子,最容易忍不住想做點什麼。"
                    "其實靜靜看懂原因,就是今天最好的動作。"
                    "你已經把數據看完了,剩下的交給時間。")
        if weighted_change >= 1.5:
            return ("順風的日子,心情好是應該的。"
                    "也提醒自己:今天的好數字和昨天的壞數字,都只是過程的一格畫面。"
                    "維持自己的節奏,比追著行情跑更重要。")
        return ("平靜的一天,市場在等方向,你不用替它著急。"
                "每天花五分鐘看懂自己的庫存,這個習慣本身就在保護你。")

    # ── 15a「今天為什麼值得看」──────────────────────────────

    def _why_today(self, holdings: List[_Holding], weighted_change: float,
                   market_change: float, fact: dict, trade_date: date) -> dict:
        chips = [
            _chip("📊 庫存加權", "各檔漲跌 × 市值權重",
                  f"{weighted_change:+.2f}%",
                  "Σ(各檔漲跌幅 × 市值權重)", trade_date),
            _chip("📊 大盤", "TAIEX change_percent",
                  f"{market_change:+.2f}%",
                  "(今收 − 昨收) ÷ 昨收 × 100%", trade_date),
        ]
        if not holdings:
            text = "今天還沒有持股資料;加入持股後,AI 每天收盤後幫你整理一包。"
        elif fact.get("flashcard"):
            text = f"觸發閃卡:{fact['flashcard']['event_text']};庫存加權 {weighted_change:+.2f}%、大盤 {market_change:+.2f}%。"
        else:
            mover = max(holdings, key=lambda h: abs(h.change))
            text = (f"庫存加權 {weighted_change:+.2f}%、大盤 {market_change:+.2f}%;"
                    f"動最多的是 {mover.name}({mover.change:+.2f}%),原因都拆在卡包裡。")
        return {"text": text, "chips": chips}

    # ── 15j 卡包架 ───────────────────────────────────────────

    def get_shelf(self, user_id: str = "demo-user") -> dict:
        trade_date = pack_trade_date()
        holdings = sorted(_load_holdings(self.db, user_id),
                          key=lambda h: h.weight_percent, reverse=True)
        packs = []
        for h in holdings:
            has_new = abs(h.change) >= 2.0
            packs.append({
                "symbol": h.symbol,
                "name": h.name,
                "industry": h.industry,
                "subtitle": (f"收盤 {h.close:,.2f} · {h.change:+.2f}%"
                             if h.close is not None else f"{h.change:+.2f}%"),
                "has_new_insight": has_new,
                "insight_note": (f"單日 {h.change:+.2f}%,今天值得打開看看" if has_new else None),
            })

        # 歷史卡片圖鑑:已存的每日包,每包 3 張;閃卡另計
        rows = self.db.scalars(
            select(DailyPackModel)
            .where(DailyPackModel.user_id == user_id)
            .order_by(DailyPackModel.trade_date.desc())
        ).all()
        collected = 0
        recent: list = []
        for row in rows:
            payload = json.loads(row.pack_json)
            kinds = ["fact", "inference", "companion"]
            if payload.get("fact", {}).get("flashcard"):
                kinds[0] = "flash"
            collected += 3
            if len(recent) < 6:
                d = row.trade_date
                for k in kinds:
                    if len(recent) < 6:
                        recent.append({"kind": k, "date_text": f"{d.month}/{d.day}"})
        return {
            "packs": packs,
            "collected_count": collected,
            "recent_cards": recent,
            "more_count": max(0, collected - len(recent)),
        }

    # ── 15k 週末體檢:AI 本週誠實度(照實對帳) ────────────────

    def get_weekly_checkup(self, user_id: str = "demo-user") -> dict:
        today = pack_trade_date()
        monday = today - timedelta(days=today.weekday())
        week_no = int(today.strftime("%V"))
        week_label = (f"{today.year} 年 · 第 {week_no} 週"
                      f"({monday.month}/{monday.day}–{today.month}/{today.day})")

        holdings = _load_holdings(self.db, user_id)
        market_change = get_live_market_change(self.db)
        by_symbol = {h.symbol: h for h in holdings}
        tech_pct = round(sum(h.weight_percent for h in holdings if h.is_tech), 1)
        weighted_change = (
            sum(h.change * h.weight_percent for h in holdings) / 100.0
            if holdings else 0.0
        )

        # 本週(不含今日)存過的 claims → 用「現在的數據」照實對帳
        rows = self.db.scalars(
            select(DailyPackModel).where(and_(
                DailyPackModel.user_id == user_id,
                DailyPackModel.trade_date >= monday,
                DailyPackModel.trade_date < today,
            )).order_by(DailyPackModel.trade_date.desc())
        ).all()

        recon: list = []
        seen_kinds: set = set()
        for row in rows:
            for claim in json.loads(row.pack_json).get("claims", []):
                kind = claim.get("kind")
                if kind in seen_kinds or len(recon) >= 3:
                    continue
                seen_kinds.add(kind)
                recon.append(self._verify_claim(
                    claim, by_symbol, tech_pct, market_change, today
                ))

        if not recon:
            recon.append({
                "statement": "本週還沒有可對帳的提醒",
                "outcome": "miss",
                "note": "AI 只對帳自己說過的話;本週開包天數不足,先累積幾天再回來看。",
                "chip": None,
            })

        met = sum(1 for r in recon if r["outcome"] == "met")

        tiles = [
            {
                "label": "本週組合 vs 大盤",
                "value": f"{weighted_change:+.2f}% / {market_change:+.2f}%",
                "note": "以最新收盤資料計算",
            },
            {
                "label": "科技類集中度",
                "value": f"{tech_pct:.1f}%",
                "note": "提醒線 60%" +("(已超過)" if tech_pct >= 60 else "(未超過)"),
            },
        ]

        return {
            "week_label": week_label,
            "met_count": met,
            "total_count": len(recon),
            "rows": recon,
            "tiles": tiles,
            "special_pack_note": f"回顧本週 AI 說過的話 + 組合體檢,共 {len(recon) + 1} 張卡",
        }

    def _verify_claim(self, claim: dict, by_symbol: dict,
                      tech_pct: float, market_change: float, today: date) -> dict:
        kind = claim.get("kind")
        statement = claim.get("statement", "")
        chip = None
        met = False
        note = ""

        if kind == "volatility":
            h = by_symbol.get(claim.get("symbol"))
            current = h.change if h else 0.0
            met = h is not None and abs(current) >= float(claim.get("threshold", 1.5))
            name = claim.get("name", claim.get("symbol", ""))
            if h is None:
                note = f"{name} 已不在庫存中,無法對帳,列為未發生。"
            elif met:
                note = f"應驗:{name} 最新單日 {current:+.2f}%,波動確實延續了。"
            else:
                note = f"AI 這次說錯了:{name} 最新單日只有 {current:+.2f}%,波動沒有延續。"
            chip = _chip("📊 漲跌幅", f"{claim.get('symbol')} change_percent",
                         f"{current:+.2f}%", "|最新單日漲跌幅| 是否 ≥ 1.5%", today)
        elif kind == "concentration":
            met = tech_pct >= float(claim.get("threshold", 60.0))
            if met:
                note = f"應驗:科技類集中度最新 {tech_pct:.1f}%,仍高於 60% 提醒線。"
            else:
                note = f"未發生:集中度已降到 {tech_pct:.1f}%,低於提醒線——AI 這次說錯了。"
            chip = _chip("📊 產業占比", "科技類市值權重",
                         f"{tech_pct:.1f}%", "Σ(科技類市值) ÷ 總市值,是否 ≥ 60%", today)
        elif kind == "market":
            met = abs(market_change) >= float(claim.get("threshold", 1.0))
            if met:
                note = f"應驗:大盤最新單日 {market_change:+.2f}%,起伏確實比較大。"
            else:
                note = f"未發生:大盤最新單日 {market_change:+.2f}%,已恢復平靜——AI 這次說錯了。"
            chip = _chip("📊 大盤", "TAIEX change_percent",
                         f"{market_change:+.2f}%", "|最新單日漲跌幅| 是否 ≥ 1%", today)
        else:
            note = "這則提醒沒有可驗證的數據欄位,列為未發生。"

        return {
            "statement": statement,
            "outcome": "met" if met else "miss",
            "note": note,
            "chip": chip,
        }
