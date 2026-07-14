"""每日抽卡包 + AI 信任系統服務(spec 06 · 15a–15k,取代御神籤)。

資料來源(專案模擬):CMoney 提供 2025 全年資料(`raw` schema)。
後端以「今天 − 1 年」作為模擬交易日,取當天收盤/法人/動能/同學會資料分析,
分析後把數字交給 AI(OpenAI)生成推論結論措辭;AI 離線走規則式 fallback。

設計原則(信任系統五大機制):
- 事實卡全部以模擬日實際數據計算,每句結論掛出處 chip(欄位/原始值/算法/資料日期/來源)
- 推理鏈每步是數字組合,不是形容詞;AI 只負責措辭,數字由後端算好
- 閃卡觸發條件必須是寫死的數據事件(創歷史新高/創N日新高/法人連續買超/除息倒數/±3%),
  一律用 CMoney 官方旗標或閾值,絕不是 AI 判斷
- 社群卡/溫度計(股票同學會):只顯示相對這檔自身歷史基準的變化,不顯示絕對多空比
- 產生卡包時同步存下可對帳的 claims,週末體檢照實對帳(說錯也原樣寫出)
每人每交易日一包,存檔後全天一致。
"""
import json
import logging
from datetime import date, datetime, timedelta
from typing import List, Optional, Tuple
from zoneinfo import ZoneInfo

from sqlalchemy import select, and_
from sqlalchemy.orm import Session

from app.models.daily_pack import DailyPackModel
from app.models.stock_daily_price import StockDailyPrice
from app.services.services import get_live_market_change, run_async
from app.services.portfolio_analysis_service import _load_holdings, _Holding, TECH_INDUSTRY_KEYWORDS
from app.services.cmoney_service import (
    CMoneyDataService, simulated_target, effective_trade_date,
    DATA_SOURCE, FORUM_SOURCE,
)

logger = logging.getLogger(__name__)

TAIPEI = ZoneInfo("Asia/Taipei")

WEEKDAYS = ["一", "二", "三", "四", "五", "六", "日"]

FALLBACK_SOURCE = "台灣證交所收盤行情"

# 全 App 禁字:AI 生成文字若含任一禁字,直接丟棄改用規則式 fallback
BANNED_WORDS = ("建議", "買進", "賣出", "加碼", "減碼", "停損", "停利",
                "攤平", "進場", "出場", "獲利了結", "目標價")


def _now_taipei() -> datetime:
    return datetime.now(TAIPEI)


def pack_trade_date(now: Optional[datetime] = None) -> date:
    """今日卡包對應的(真實)日期:14:30 前算前一日(收盤後更新)。
    now 為 None 時交給 effective_trade_date 處理(含模擬時鐘覆寫);
    帶明確 now(單元測試)則照 14:30 規則、忽略覆寫。"""
    return effective_trade_date(now)


def _wan_text(value: float) -> str:
    """金額 → 「532.7萬」;不足一萬顯示整數元。"""
    if value >= 10000:
        return f"{value / 10000:,.1f}萬"
    return f"{value:,.0f}"


def _date_text(d: date) -> str:
    return f"{d.year}/{d.month:02d}/{d.day:02d} · 週{WEEKDAYS[d.weekday()]}"


def _chip(label: str, field: str, raw_value: str, formula: str,
          data_date: date, source: str = DATA_SOURCE) -> dict:
    return {
        "label": label,
        "field": field,
        "raw_value": raw_value,
        "formula": formula,
        "data_date": data_date.isoformat(),
        "source": source,
    }


def _contains_banned(text_value: str) -> bool:
    return any(word in text_value for word in BANNED_WORDS)


class _CMoneyContext:
    """一次卡包計算所需的 CMoney 模擬日上下文。"""

    def __init__(self, cm: CMoneyDataService, yyyymmdd: str):
        self.cm = cm
        self.yyyymmdd = yyyymmdd
        self.sim_date = cm.to_date(yyyymmdd)


class DailyPackService:
    def __init__(self, db: Session):
        self.db = db

    # ── CMoney 模擬日上下文(今天 − 1 年 → 最近交易日) ─────────

    def _cmoney_context(self, trade_date: date) -> Optional[_CMoneyContext]:
        cm = CMoneyDataService(self.db)
        if not cm.available:
            return None
        yyyymmdd = cm.resolve_trade_date(simulated_target(trade_date))
        if not yyyymmdd:
            return None
        ctx = _CMoneyContext(cm, yyyymmdd)
        # 模擬日收盤資料 upsert 進 public 表(冪等),讓全 App 吃同一份數據
        cm.sync_public_tables(trade_date, yyyymmdd)
        return ctx

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
            # 舊版卡包(陪伴卡時代)沒有社群卡 → 當場重生,自動遷移到新格式
            if "community_card" in payload:
                payload["opened"] = bool(row.opened)
                return payload
        if row:
            # force 重生(測試用)或舊格式遷移:丟棄今日包,依當下持股重算
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

    # ── 卡包內容 ─────────────────────────────────────────────

    def _build_pack(self, user_id: str, trade_date: date) -> dict:
        ctx = self._cmoney_context(trade_date)
        # sync 之後 _load_holdings 讀到的就是 CMoney 模擬日收盤價
        holdings = _load_holdings(self.db, user_id)

        market_change = ctx.cm.market_change(ctx.yyyymmdd) if ctx else None
        if market_change is None:
            market_change = get_live_market_change(self.db)

        data_date = ctx.sim_date if ctx else trade_date
        total_value = sum(h.market_value for h in holdings)
        weighted_change = (
            sum(h.change * h.weight_percent for h in holdings) / 100.0
            if holdings else 0.0
        )

        fact = self._fact_card(holdings, total_value, weighted_change, data_date, ctx)
        community = self._community_meter(holdings, ctx)
        community_card = self._community_card(holdings, ctx, data_date)
        inference, claims = self._inference_card(
            holdings, weighted_change, market_change, data_date, community
        )
        why_today = self._why_today(holdings, weighted_change, market_change, fact, data_date)

        # 分析完成 → 數字交給 AI 措辭(推論結論);失敗保留規則式
        self._apply_ai_texts(
            inference=inference,
            user_id=user_id,
            holdings=holdings, weighted_change=weighted_change,
            market_change=market_change, community=community,
            flashcard=fact.get("flashcard"),
        )

        return {
            "date_text": _date_text(trade_date),
            "data_date": data_date.isoformat(),
            "data_source_note": (f"CMoney 2025 模擬資料 · 模擬交易日 {data_date.isoformat()}"
                                 if ctx else "台灣證交所收盤行情"),
            "holdings_count": len(holdings),
            "total_value_text": _wan_text(total_value),
            "why_today": why_today,
            "fact": fact,
            "inference": inference,
            "community_card": community_card,
            "community": community,
            # 內部欄位:15k 對帳用,schema 不外露
            "claims": claims,
        }

    # ── 事實卡(15f):可驗證的庫存數據 ───────────────────────

    def _fact_card(self, holdings: List[_Holding], total_value: float,
                   weighted_change: float, data_date: date,
                   ctx: Optional[_CMoneyContext]) -> dict:
        source = DATA_SOURCE if ctx else FALLBACK_SOURCE
        total_chip = _chip(
            "📊 庫存市值", "收盤價 × 股數(逐檔加總)",
            f"{total_value:,.0f} 元",
            "Σ(各檔模擬日收盤價 × 持有股數)", data_date, source,
        )

        stocks = []
        ordered = sorted(holdings, key=lambda h: h.weight_percent, reverse=True)
        for i, h in enumerate(ordered):
            rows = [
                {
                    "label": "收盤價",
                    "value": f"{h.close:,.2f}" if h.close is not None else "—",
                    "chip": _chip("📊 收盤行情", f"{h.symbol} 收盤價",
                                  f"{h.close:,.2f}" if h.close is not None else "無資料",
                                  "模擬日收盤價,未經任何調整", data_date, source),
                },
                {
                    "label": "今日漲跌",
                    "value": f"{h.change:+.2f}%",
                    "chip": _chip("📊 漲跌幅", f"{h.symbol} 漲幅(%)",
                                  f"{h.change:+.2f}%",
                                  "(今收 − 昨收) ÷ 昨收 × 100%", data_date, source),
                },
                {
                    "label": "庫存占比",
                    "value": f"{h.weight_percent:.1f}%",
                    "chip": _chip("📊 占比", f"{h.symbol} 市值權重",
                                  f"{h.market_value:,.0f} 元",
                                  "該檔市值 ÷ 庫存總市值 × 100%", data_date, source),
                },
            ]
            # CMoney 法人資料(spec 15f:收盤/外資持股/法人買超)
            if ctx:
                inst = ctx.cm.get_institutional(h.symbol, ctx.yyyymmdd)
                if inst and inst.foreign_ratio is not None:
                    rows.append({
                        "label": "外資持股",
                        "value": f"{inst.foreign_ratio:.2f}%",
                        "chip": _chip("📊 外資持股", f"{h.symbol} 外資持股比率(%)",
                                      f"{inst.foreign_ratio:.2f}%",
                                      "外資持股張數 ÷ 發行張數 × 100%", data_date),
                    })
                if inst and inst.net_buy_total is not None:
                    rows.append({
                        "label": "法人買賣超",
                        "value": f"{inst.net_buy_total:+,.0f} 張",
                        "chip": _chip("📊 法人買賣超", f"{h.symbol} 買賣超合計",
                                      f"{inst.net_buy_total:+,.1f} 張",
                                      "外資 + 投信 + 自營商 當日買賣超合計", data_date),
                    })
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
            "footnote": "以上都是收盤後的客觀數據,你在券商 App(對照 2025 年)也查得到",
            "flashcard": self._flashcard(ordered, data_date, ctx),
        }

    # ── 閃卡:寫死的數據事件(spec:創年內新高/法人連買/除息倒數) ──

    def _flashcard(self, holdings: List[_Holding], data_date: date,
                   ctx: Optional[_CMoneyContext]) -> Optional[dict]:
        if ctx:
            for h in holdings:
                momentum = ctx.cm.get_momentum(h.symbol, ctx.yyyymmdd)
                if momentum and momentum.all_time_high:
                    return {
                        "event_text": f"{h.name} 股價創歷史新高",
                        "chip": _chip("📊 動能旗標", f"{h.symbol} 股價創歷史新高",
                                      "1(是)",
                                      "CMoney 官方旗標:收盤價 ≥ 歷史最高收盤(寫死條件,非 AI 判斷)",
                                      data_date),
                    }
                if momentum and momentum.n_day_high >= 60:
                    return {
                        "event_text": f"{h.name} 收盤價創近 {momentum.n_day_high} 日新高",
                        "chip": _chip("📊 動能旗標", f"{h.symbol} 股價創N日新高",
                                      str(momentum.n_day_high),
                                      "CMoney 官方旗標:N ≥ 60(寫死門檻,非 AI 判斷)",
                                      data_date),
                    }
                inst = ctx.cm.get_institutional(h.symbol, ctx.yyyymmdd)
                if inst and inst.consecutive_buy_days >= 5:
                    return {
                        "event_text": f"{h.name} 法人連續買超 {inst.consecutive_buy_days} 個交易日",
                        "chip": _chip("📊 法人買賣超", f"{h.symbol} 買賣超合計",
                                      f"連續 {inst.consecutive_buy_days} 日 > 0",
                                      "連續買超天數 ≥ 5(寫死門檻,非 AI 判斷)", data_date),
                    }
                ex_days = ctx.cm.days_to_ex_dividend(h.symbol, ctx.sim_date)
                if ex_days is not None and 0 < ex_days <= 3:
                    return {
                        "event_text": f"{h.name} 除息日倒數 {ex_days} 天",
                        "chip": _chip("📊 除息日", f"{h.symbol} 除息日",
                                      f"{ex_days} 天後",
                                      "除息日 − 模擬日 ≤ 3 天(寫死門檻,非 AI 判斷)", data_date),
                    }

        # 通用門檻:單日 ±3%
        for h in holdings:
            if abs(h.change) >= 3.0:
                direction = "上漲" if h.change > 0 else "下跌"
                return {
                    "event_text": f"{h.name} 單日{direction} {abs(h.change):.2f}%(達 ±3% 事件門檻)",
                    "chip": _chip("📊 漲跌幅", f"{h.symbol} 漲幅(%)",
                                  f"{h.change:+.2f}%",
                                  "|單日漲跌幅| ≥ 3%(寫死門檻,非 AI 判斷)", data_date,
                                  DATA_SOURCE if ctx else FALLBACK_SOURCE),
                }

        # 無 CMoney 資料時的舊路徑:權重最高一檔收盤創近 60 日新高
        if not ctx:
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
                                      f"今日收盤 ≥ 近 {len(history)} 日收盤最大值(寫死條件)",
                                      data_date, FALLBACK_SOURCE),
                    }
        return None

    # ── 社群溫度計(股票同學會 raw_10):只看相對自身基準的變化 ──

    def _community_meter(self, holdings: List[_Holding],
                         ctx: Optional[_CMoneyContext]) -> Optional[dict]:
        if not ctx or not holdings:
            return None

        posts_sum = 0
        bullish_sum = 0
        baseline_sum = 0.0
        baseline_ratio_num = 0.0
        baseline_ratio_den = 0
        for h in holdings:
            forum = ctx.cm.get_forum(h.symbol, ctx.sim_date)
            if not forum:
                continue
            posts_sum += forum.posts
            bullish_sum += forum.bullish
            if forum.baseline_posts_avg:
                baseline_sum += forum.baseline_posts_avg
            if forum.baseline_bullish_ratio is not None:
                baseline_ratio_num += forum.baseline_bullish_ratio
                baseline_ratio_den += 1

        if posts_sum == 0 or baseline_sum <= 0:
            return None

        heat_percent = round((posts_sum / baseline_sum - 1) * 100, 1)
        heat_text = (f"你的持股在同學會的討論熱度,比近 20 日平均"
                     f"{'高' if heat_percent >= 0 else '低'} {abs(heat_percent):.0f}%")

        sentiment_text = None
        if baseline_ratio_den > 0 and posts_sum > 0:
            today_ratio = bullish_sum / posts_sum * 100
            baseline_ratio = baseline_ratio_num / baseline_ratio_den
            shift = round(today_ratio - baseline_ratio, 1)
            sentiment_text = (f"看多聲量占比比自己的近期基準"
                              f"{'高' if shift >= 0 else '低'} {abs(shift):.1f} 個百分點")

        return {
            "heat_percent": heat_percent,
            "heat_text": heat_text,
            "sentiment_text": sentiment_text,
            "note": "社群情緒 ≠ 買賣訊號;只顯示相對你持股自身歷史基準的變化",
            "chip": _chip("💬 同學會討論", "發文則數(持股加總)",
                          f"今日 {posts_sum} 則 / 近 20 日均 {baseline_sum:.0f} 則",
                          "今日發文則數 ÷ 近 20 日平均 − 1", ctx.sim_date, FORUM_SOURCE),
        }

    # ── 推論卡(15g):每步是數字,附出處 chip ─────────────────

    def _inference_card(self, holdings: List[_Holding], weighted_change: float,
                        market_change: float, data_date: date,
                        community: Optional[dict]) -> Tuple[dict, list]:
        claims: list = []
        if not holdings:
            inference = {
                "conclusion": "目前沒有持股,市場的波動暫時與你的資產無關。",
                "terms": [],
                "steps": [{
                    "number": 1,
                    "text": "庫存檔數 0,庫存市值 0 元 —— 沒有部位,就沒有需要判斷的風險。",
                    "chip": _chip("📊 庫存", "持股檔數", "0 檔", "持股資料表逐筆計數",
                                  data_date, FALLBACK_SOURCE),
                    "glossary": None,
                }],
                "caveat": "這是 AI 依上列數字做的推論,可能有錯;但每一步用到的數字都查得到。",
            }
            return inference, claims

        tech_pct = round(sum(h.weight_percent for h in holdings if h.is_tech), 1)
        top = max(holdings, key=lambda h: h.weight_percent)
        ratio = (weighted_change / market_change) if abs(market_change) >= 0.3 else None

        # 結論句(規則式 fallback;AI 可覆寫措辭,數字不變)
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
                              "Σ(科技類個股市值) ÷ 庫存總市值 × 100%", data_date),
                "glossary": None,
            },
            {
                "number": 2,
                "text": (f"今日大盤 {market_change:+.2f}%,你的庫存加權 {weighted_change:+.2f}%"
                         + (f",波動倍率約 {abs(ratio):.1f} 倍。" if ratio is not None else "。")),
                "chip": _chip("📊 相對波動", "庫存加權漲跌 ÷ 大盤漲跌",
                              f"{weighted_change:+.2f}% / {market_change:+.2f}%",
                              "Σ(各檔漲跌 × 市值權重) 與市值加權大盤 proxy 比較", data_date),
                "glossary": None,
            },
        ]

        # 第 3 步:有同學會資料時用社群熱度,否則行為財務學說明
        if community:
            steps.append({
                "number": 3,
                "text": (f"{community['heat_text']};"
                         "討論變熱只代表關注變多,歷史上熱度與隔日漲跌沒有穩定關係。"),
                "chip": community["chip"],
                "glossary": {
                    "term": "社群溫度計",
                    "definition": ("把你持股在股票同學會的當日發文量,和它自己近 20 日的平均比較。"
                                   "只看相對變化、不看絕對多空比,因為聲量大小因股而異;"
                                   "社群情緒不是買賣訊號。"),
                },
            })
        else:
            steps.append({
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
            })

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
                "date": data_date.isoformat(),
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
                "date": data_date.isoformat(),
            })
        if abs(market_change) >= 1.0:
            claims.append({
                "kind": "market",
                "statement": f"大盤單日 {market_change:+.2f}%,整體市場情緒起伏可能放大(|漲跌| ≥ 1%)",
                "threshold": 1.0,
                "baseline": market_change,
                "date": data_date.isoformat(),
            })

        inference = {
            "conclusion": conclusion,
            "terms": terms,
            "steps": steps,
            "caveat": "這是 AI 依上列數字做的推論,可能有錯;但每一步用到的數字都查得到。",
        }
        return inference, claims

    # ── 社群卡(15h · 同學會溫度計):討論量 + 多空溫度,只比自身基準 ──

    NOTE_COMMUNITY = ("社群情緒 ≠ 買賣訊號,但能告訴你現在的氣氛。"
                      "社群結構性偏多,所以只跟這檔自己的歷史基準比。")

    def _community_card(self, holdings: List[_Holding],
                        ctx: Optional[_CMoneyContext], data_date: date) -> dict:
        """聚焦「同學會討論最熱」的一檔;鐵則:只顯示相對自身 30 日基準的變化,
        絕不顯示絕對多空比(社群結構性偏多)。無資料時回資料不足態。"""
        focus: Optional[_Holding] = None
        forum = None
        if ctx:
            for h in holdings:
                f = ctx.cm.get_forum(h.symbol, ctx.sim_date, baseline_days=30)
                if not f or f.posts <= 0 or not f.baseline_posts_avg:
                    continue
                if forum is None or f.posts > forum.posts:
                    focus, forum = h, f

        if not focus or not forum:
            top = max(holdings, key=lambda h: h.weight_percent) if holdings else None
            return {
                "stock_name": top.name if top else "我的持股",
                "stock_symbol": top.symbol if top else "",
                "has_data": False,
                "posts_today": 0,
                "posts_baseline": 0.0,
                "heat_text": "今天沒有足夠的同學會資料;資料齊備時,這裡會顯示討論熱度與多空溫度。",
                "baseline_tick_percent": 50.0,
                "sentiment_shift_percent": None,
                "sentiment_text": None,
                "bullish": 0,
                "bearish": 0,
                "neutral": 0,
                "note": self.NOTE_COMMUNITY,
                "chip": None,
            }

        ratio = forum.posts / forum.baseline_posts_avg
        # 白色刻度線 = 均值在「今日討論量滿版條」上的位置;夾在 4–96% 免貼邊
        tick = min(max(forum.baseline_posts_avg / forum.posts * 100, 4.0), 96.0)
        heat_text = f"討論熱度是這檔 30 日均值的 {ratio:.1f} 倍"

        shift = None
        sentiment_text = None
        if forum.baseline_bullish_ratio is not None and forum.posts > 0:
            today_ratio = forum.bullish / forum.posts * 100
            shift = round(today_ratio - forum.baseline_bullish_ratio, 1)
            direction = "多" if shift >= 0 else "空"
            sentiment_text = (f"較自身基準偏{direction} {shift:+.0f}%"
                              f"(多 {forum.bullish}/空 {forum.bearish}/中性 {forum.neutral})")

        return {
            "stock_name": focus.name,
            "stock_symbol": focus.symbol,
            "has_data": True,
            "posts_today": forum.posts,
            "posts_baseline": round(forum.baseline_posts_avg, 1),
            "heat_text": heat_text,
            "baseline_tick_percent": round(tick, 1),
            "sentiment_shift_percent": shift,
            "sentiment_text": sentiment_text,
            "bullish": forum.bullish,
            "bearish": forum.bearish,
            "neutral": forum.neutral,
            "note": self.NOTE_COMMUNITY,
            "chip": _chip("📊 同學會發文統計", f"{focus.symbol} 發文則數/看多/看空/中性",
                          f"今日 {forum.posts} 則 / 30 日均 {forum.baseline_posts_avg:.0f} 則",
                          "今日發文則數 ÷ 30 日均值;看多占比 − 自身 30 日看多占比均值",
                          ctx.sim_date, FORUM_SOURCE),
        }

    # ── 分析後交給 AI:數字算好 → AI 只負責措辭,禁字直接退回 ──

    def _apply_ai_texts(self, inference: dict, user_id: str,
                        holdings: List[_Holding], weighted_change: float,
                        market_change: float, community: Optional[dict],
                        flashcard: Optional[dict]) -> None:
        from app.services.openai_service import OpenAIService
        metrics = {
            "holdings": [
                {"name": h.name, "symbol": h.symbol,
                 "change_percent": round(h.change, 2),
                 "weight_percent": h.weight_percent,
                 "industry": h.industry}
                for h in holdings
            ],
            "weighted_change": round(weighted_change, 2),
            "market_change": round(market_change, 2),
            "community_heat_text": community["heat_text"] if community else None,
            "flashcard_event": flashcard["event_text"] if flashcard else None,
        }
        try:
            from app.services.investment_profile_service import InvestmentProfileService
            metrics["user_prompt_context"] = InvestmentProfileService(self.db).prompt_context(user_id)["prompt_text"]
        except Exception:
            metrics["user_prompt_context"] = ""
        try:
            data = run_async(OpenAIService.fetch_pack_ai_text(metrics)) or {}
        except Exception:
            data = {}

        conclusion = data.get("conclusion")
        if isinstance(conclusion, str) and conclusion.strip() and not _contains_banned(conclusion):
            inference["conclusion"] = conclusion.strip()

    # ── 15a「今天為什麼值得看」──────────────────────────────

    def _why_today(self, holdings: List[_Holding], weighted_change: float,
                   market_change: float, fact: dict, data_date: date) -> dict:
        chips = [
            _chip("📊 庫存加權", "各檔漲跌 × 市值權重",
                  f"{weighted_change:+.2f}%",
                  "Σ(各檔漲跌幅 × 市值權重)", data_date),
            _chip("📊 大盤", "市值比重加權漲幅(proxy)",
                  f"{market_change:+.2f}%",
                  "Σ(市值比重 × 漲幅) ÷ Σ(市值比重)", data_date),
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
        # 卡包架收藏的是「每天抽過的一整包」,不是每檔持股各一包。
        # 直接使用當時存下的快照,避免回顧歷史日期時混入今天的持股或行情。
        rows = self.db.scalars(
            select(DailyPackModel)
            .where(DailyPackModel.user_id == user_id)
            .order_by(DailyPackModel.trade_date.desc())
        ).all()
        packs: list = []
        collected = 0
        recent: list = []
        for row in rows:
            payload = json.loads(row.pack_json)
            # 陪伴卡舊格式無法完整回顧目前的三卡畫面,只保留在圖鑑計數中。
            if "community_card" in payload:
                payload["opened"] = bool(row.opened)
                flashcard = payload.get("fact", {}).get("flashcard")
                holdings_count = int(payload.get("holdings_count", 0))
                packs.append({
                    "trade_date": row.trade_date.isoformat(),
                    "date_text": payload.get("date_text", _date_text(row.trade_date)),
                    "content_title": (
                        flashcard.get("event_text") if flashcard
                        else f"{holdings_count} 檔庫存 · 3 張分析卡"
                    ),
                    "content_summary": payload.get("why_today", {}).get("text", "當日卡包回顧"),
                    "data_date": payload.get("data_date", row.trade_date.isoformat()),
                    "has_new_insight": flashcard is not None,
                    "pack": payload,
                })
            kinds = ["fact", "inference", "community"]
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
        ctx = self._cmoney_context(today)   # 對帳一律用「現在」的模擬日數據
        monday = today - timedelta(days=today.weekday())
        week_no = int(today.strftime("%V"))
        week_label = (f"{today.year} 年 · 第 {week_no} 週"
                      f"({monday.month}/{monday.day}–{today.month}/{today.day})")

        holdings = _load_holdings(self.db, user_id)
        market_change = ctx.cm.market_change(ctx.yyyymmdd) if ctx else None
        if market_change is None:
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
                "note": "以最新模擬日收盤資料計算",
            },
            {
                "label": "科技類集中度",
                "value": f"{tech_pct:.1f}%",
                "note": "提醒線 60%" + ("(已超過)" if tech_pct >= 60 else "(未超過)"),
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
            chip = _chip("📊 漲跌幅", f"{claim.get('symbol')} 漲幅(%)",
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
            chip = _chip("📊 大盤", "市值比重加權漲幅(proxy)",
                         f"{market_change:+.2f}%", "|最新單日漲跌幅| 是否 ≥ 1%", today)
        else:
            note = "這則提醒沒有可驗證的數據欄位,列為未發生。"

        return {
            "statement": statement,
            "outcome": "met" if met else "miss",
            "note": note,
            "chip": chip,
        }
