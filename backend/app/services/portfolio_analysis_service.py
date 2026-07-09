"""庫存分析(8a/8b/8c)與個股 AI 觀點(8d/8e)服務。

全部以資料庫內的持股、股票基本資料與最新日價計算,
規則式產生安撫語氣的文字內容,不依賴外部 LLM,確保回應穩定快速。
"""
from sqlalchemy.orm import Session
from typing import List, Optional

from app.repositories.repositories import PortfolioRepository, StockRepository
from app.services.services import AnxietyScoreService, get_live_market_change, is_finite_number

# 視為「科技類」的產業關鍵字(曝險集中提醒用)
TECH_INDUSTRY_KEYWORDS = ("半導體", "IC", "電子", "光電", "通信", "電腦", "科技")

OTHER_INDUSTRY = "其他"


def _clamp(value: float, low: float, high: float) -> float:
    return max(low, min(high, value))


class _MergedLots:
    """同一檔股票可能分散在多個券商 lot;分析一律以 symbol 聚合,
    股數加總、成本以股數加權平均,避免同一檔重複出現。"""

    def __init__(self, lots):
        self.id = lots[0].id
        self.symbol = lots[0].symbol
        self.shares = sum(l.shares or 0 for l in lots)
        costed = [
            ((l.shares or 0), float(l.cost_price))
            for l in lots
            if (l.shares or 0) > 0 and is_finite_number(l.cost_price)
        ]
        costed_shares = sum(s for s, _ in costed)
        self.cost_price = (
            sum(s * c for s, c in costed) / costed_shares if costed_shares > 0 else None
        )


class _Holding:
    def __init__(self, item, stock, price):
        self.id = item.id
        self.symbol = item.symbol
        self.name = stock.name if stock else item.symbol
        self.industry = (stock.industry if stock and stock.industry else "") or OTHER_INDUSTRY
        self.shares = item.shares
        # NaN(匯入異常或早盤 Yahoo 壞資料)一律視為缺值,避免污染整個投組加總
        self.cost = float(item.cost_price) if is_finite_number(item.cost_price) else None
        self.close = float(price.close_price) if price and is_finite_number(price.close_price) else None
        self.change = float(price.change_percent) if price and is_finite_number(price.change_percent) else 0.0

        effective_price = self.close if self.close is not None else (self.cost or 0.0)
        self.market_value = effective_price * (self.shares or 0)
        self.cost_value = (self.cost or 0.0) * (self.shares or 0)
        self.has_pnl = bool(self.cost and self.shares and self.close is not None and self.cost > 0)
        self.pnl = (self.market_value - self.cost_value) if self.has_pnl else 0.0
        self.pnl_percent = ((self.close - self.cost) / self.cost * 100.0) if self.has_pnl else 0.0
        self.weight_percent = 0.0  # filled in later

    @property
    def is_tech(self) -> bool:
        return any(kw in self.industry for kw in TECH_INDUSTRY_KEYWORDS)


def _load_holdings(db: Session, user_id: str) -> List[_Holding]:
    portfolio_repo = PortfolioRepository(db)
    stock_repo = StockRepository(db)

    by_symbol: dict = {}
    for item in portfolio_repo.get_items(user_id):
        if item.status == "exited":
            continue
        by_symbol.setdefault(item.symbol, []).append(item)

    holdings = []
    for symbol, lots in by_symbol.items():
        stock = stock_repo.get_stock(symbol)
        price = stock_repo.get_daily_price(symbol)
        holdings.append(_Holding(_MergedLots(lots), stock, price))

    total = sum(h.market_value for h in holdings)
    if total > 0:
        for h in holdings:
            h.weight_percent = round(h.market_value / total * 100.0, 1)
    return holdings


class PortfolioAnalysisService:
    def __init__(self, db: Session):
        self.db = db

    def get_analysis(self, user_id: str = "demo-user") -> dict:
        holdings = _load_holdings(self.db, user_id)
        if not holdings:
            return self._empty_analysis()

        total_value = sum(h.market_value for h in holdings)
        total_cost = sum(h.cost_value for h in holdings)
        pnl = total_value - total_cost
        pnl_percent = (pnl / total_cost * 100.0) if total_cost > 0 else 0.0

        exposure = self._exposure(holdings)
        tech_percent = round(sum(h.weight_percent for h in holdings if h.is_tech), 1)
        risk_score, risk_note = self._risk_score(holdings, exposure, tech_percent)
        anxiety = AnxietyScoreService(self.db).calculate_anxiety(user_id)
        notices = self._risk_notices(holdings, exposure, tech_percent)

        return {
            "total_market_value": round(total_value, 0),
            "total_cost": round(total_cost, 0),
            "unrealized_pnl": round(pnl, 0),
            "unrealized_pnl_percent": round(pnl_percent, 2),
            "holdings_count": len(holdings),
            "risk_score": risk_score,
            "risk_note": risk_note,
            "anxiety_score": anxiety["score"],
            "anxiety_note": anxiety["main_reason"],
            "exposure": exposure,
            "tech_exposure_percent": tech_percent,
            "exposure_note": self._exposure_note(exposure, tech_percent),
            "holdings": [
                {
                    "id": h.id,
                    "symbol": h.symbol,
                    "name": h.name,
                    "industry": h.industry,
                    "shares": h.shares,
                    "cost_price": h.cost,
                    "close_price": h.close,
                    "market_value": round(h.market_value, 0),
                    "pnl": round(h.pnl, 0),
                    "pnl_percent": round(h.pnl_percent, 2),
                    "weight_percent": h.weight_percent,
                    "change_percent": round(h.change, 2),
                }
                for h in sorted(holdings, key=lambda x: x.weight_percent, reverse=True)
            ],
            "risk_notices": notices,
        }

    # ── 內部規則 ─────────────────────────────────────────────

    def _empty_analysis(self) -> dict:
        return {
            "total_market_value": 0, "total_cost": 0,
            "unrealized_pnl": 0, "unrealized_pnl_percent": 0,
            "holdings_count": 0,
            "risk_score": 0, "risk_note": "尚未加入持股,還沒有可分析的資料",
            "anxiety_score": 30, "anxiety_note": "無持股狀態,市場波動不影響你",
            "exposure": [], "tech_exposure_percent": 0,
            "exposure_note": "加入持股後,這裡會顯示你的產業配置。",
            "holdings": [], "risk_notices": [],
        }

    def _exposure(self, holdings: List[_Holding]) -> List[dict]:
        by_industry: dict = {}
        for h in holdings:
            by_industry[h.industry] = by_industry.get(h.industry, 0.0) + h.weight_percent
        segments = [
            {"industry": industry, "percent": round(percent, 1)}
            for industry, percent in by_industry.items()
        ]
        segments.sort(key=lambda s: s["percent"], reverse=True)
        return segments

    def _exposure_note(self, exposure: List[dict], tech_percent: float) -> str:
        if not exposure:
            return "加入持股後,這裡會顯示你的產業配置。"
        top = exposure[0]
        if tech_percent >= 60:
            return (
                f"科技相關產業合計約 {tech_percent:.1f}%,若半導體景氣循環轉弱,"
                "整體投組可能同步波動。不需要急著調整,先知道自己的組合長什麼樣子就好。"
            )
        if top["percent"] >= 50:
            return (
                f"目前「{top['industry']}」佔比約 {top['percent']:.1f}%,單一產業比重偏高。"
                "了解自己的配置,是安心投資的第一步。"
            )
        return "你的產業配置相對分散,單一產業的波動對整體影響有限,可以放心觀察。"

    def _risk_score(self, holdings: List[_Holding], exposure: List[dict], tech_percent: float):
        top_weight = max(h.weight_percent for h in holdings)
        top_industry = exposure[0]["percent"] if exposure else 0.0
        avg_volatility = sum(abs(h.change) for h in holdings) / len(holdings)

        score = int(round(_clamp(
            top_weight * 0.55 + max(top_industry, tech_percent) * 0.35 + avg_volatility * 3.0,
            5, 98
        )))

        if score >= 70:
            note = "集中度偏高,主要來自單一持股與產業比重"
        elif score >= 45:
            note = "集中度中等,留意單一產業的波動即可"
        else:
            note = "配置相對分散,風險在健康範圍內"
        return score, note

    def _risk_notices(self, holdings: List[_Holding], exposure: List[dict], tech_percent: float) -> List[dict]:
        notices = []

        top_holding = max(holdings, key=lambda h: h.weight_percent)
        if top_holding.weight_percent >= 40:
            pct_text = f"{top_holding.weight_percent:.1f}%"
            notices.append({
                "severity": "rose",
                "badge": "優先檢查",
                "title": "單一持股比重偏高",
                "body": (
                    f"{top_holding.name} 佔了你投組的 {pct_text},"
                    "只要這一檔波動,整體資產就會跟著明顯起伏。"
                ),
                "highlight": pct_text,
                "plain_talk": (
                    f"白話說:雞蛋大多放在同一個籃子裡。這不是要你馬上改變什麼,"
                    f"只是先知道:整體資產會跟著 {top_holding.name} 一起呼吸。"
                ),
            })

        if tech_percent >= 60:
            pct_text = f"{tech_percent:.1f}%"
            notices.append({
                "severity": "amber",
                "badge": "注意",
                "title": "科技產業曝險集中",
                "body": (
                    f"科技相關持股合計約 {pct_text},"
                    "當半導體或電子產業回檔時,你的投組會同步承壓。"
                ),
                "highlight": pct_text,
                "plain_talk": (
                    "白話說:你的持股大多在同一條產業鏈上,漲會一起漲、跌也會一起跌。"
                    "知道這件事,下次看到整排綠字就不會那麼慌了。"
                ),
            })
        elif exposure and exposure[0]["percent"] >= 60 and len(exposure) > 1:
            top = exposure[0]
            pct_text = f"{top['percent']:.1f}%"
            notices.append({
                "severity": "amber",
                "badge": "注意",
                "title": f"{top['industry']}比重偏高",
                "body": (
                    f"「{top['industry']}」佔投組約 {pct_text},"
                    "單一產業的消息面容易牽動你的整體損益。"
                ),
                "highlight": pct_text,
                "plain_talk": (
                    "白話說:同產業的股票常常一起漲跌,分散一點,心情也會平穩一點。"
                ),
            })

        volatile = [h for h in holdings if h.change <= -3.0]
        if volatile and len(notices) < 2:
            worst = min(volatile, key=lambda h: h.change)
            pct_text = f"{abs(worst.change):.2f}%"
            notices.append({
                "severity": "amber",
                "badge": "注意",
                "title": f"{worst.name} 今日波動較大",
                "body": (
                    f"{worst.name} 今天下跌 {pct_text},幅度比平常大。"
                    "先確認是產業齊跌還是個別事件,再決定要不要理它。"
                ),
                "highlight": pct_text,
                "plain_talk": (
                    "白話說:單日大跌不等於公司出事,先深呼吸,不要急著在盤中做決定。"
                ),
            })

        return notices


class StockInsightService:
    """個股 AI 觀點:以價格、損益與大盤對比規則式產生觀點與訊號。"""

    def __init__(self, db: Session):
        self.db = db

    def get_insights(self, user_id: str = "demo-user") -> dict:
        holdings = _load_holdings(self.db, user_id)
        items = []
        for h in sorted(holdings, key=lambda x: x.weight_percent, reverse=True):
            outlook, score = self._outlook(h)
            items.append({
                "symbol": h.symbol,
                "name": h.name,
                "industry": h.industry,
                "weight_percent": h.weight_percent,
                "outlook": outlook,
                "outlook_score": score,
                "headline": self._headline(h, outlook),
            })
        return {
            "bullish_count": sum(1 for i in items if i["outlook"] == "bullish"),
            "neutral_count": sum(1 for i in items if i["outlook"] == "neutral"),
            "caution_count": sum(1 for i in items if i["outlook"] == "caution"),
            "items": items,
        }

    def get_insight_detail(self, symbol: str, user_id: str = "demo-user") -> Optional[dict]:
        holdings = _load_holdings(self.db, user_id)
        holding = next((h for h in holdings if h.symbol == symbol), None)
        if holding is None:
            # 未持有(觀察清單 11f 點入):同一套規則,但持倉視角換成觀察視角
            return self._watch_insight_detail(symbol)

        outlook, score = self._outlook(holding)
        market_change = get_live_market_change(self.db)
        signals = self._signals(holding, market_change)

        return {
            "symbol": holding.symbol,
            "name": holding.name,
            "industry": holding.industry,
            "outlook": outlook,
            "outlook_score": score,
            "stance_label": self._stance_label(holding),
            "summary": self._summary(holding, market_change),
            "signals": signals,
            "plain_summary": self._plain_summary(holding, outlook),
        }

    def _watch_insight_detail(self, symbol: str) -> Optional[dict]:
        """觀察股(未持有)的觀點詳情:價格/大盤訊號照舊,
        第三張「你的持倉」訊號卡換成觀察視角;查無此股回 None(404)。"""
        stock_repo = StockRepository(self.db)
        stock = stock_repo.get_stock(symbol)
        if stock is None:
            return None
        price = stock_repo.get_daily_price(symbol)

        class _WatchStub:
            id = None
            shares = None
            cost_price = None

        stub = _WatchStub()
        stub.symbol = symbol
        h = _Holding(stub, stock, price)

        outlook, score = self._outlook(h)
        market_change = get_live_market_change(self.db)
        signals = self._signals(h, market_change)
        signals[-1] = {
            "source": "觀察中 · 未持有",
            "direction": "neutral",
            "direction_label": "→ 中性觀望",
            "text": "這檔還在觀察清單,不計入市值與損益;可以先留意量能與產業消息,節奏由你決定。",
        }

        return {
            "symbol": h.symbol,
            "name": h.name,
            "industry": h.industry,
            "outlook": outlook,
            "outlook_score": score,
            "stance_label": self._stance_label(h),
            "summary": self._summary(h, market_change),
            "signals": signals,
            "plain_summary": self._plain_summary(h, outlook),
        }

    # ── 規則 ────────────────────────────────────────────────

    def _outlook(self, h: _Holding):
        raw = 50.0 + h.change * 6.0 + (h.pnl_percent * 0.8 if h.has_pnl else 0.0)
        score = int(round(_clamp(raw, 8, 92)))
        if score >= 60:
            outlook = "bullish"
        elif score <= 40:
            outlook = "caution"
        else:
            outlook = "neutral"
        return outlook, score

    def _short_term(self, h: _Holding) -> str:
        if h.change <= -0.5:
            return "bearish"
        if h.change >= 0.5:
            return "bullish"
        return "neutral"

    def _long_term(self, h: _Holding) -> str:
        if not h.has_pnl:
            return "neutral"
        if h.pnl_percent >= 5:
            return "bullish"
        if h.pnl_percent <= -5:
            return "bearish"
        return "neutral"

    def _stance_label(self, h: _Holding) -> str:
        short_map = {"bullish": "短線偏多", "bearish": "短線留意", "neutral": "短線觀望"}
        long_map = {"bullish": "長線看好", "bearish": "長線保守", "neutral": "長線中性"}
        return f"{short_map[self._short_term(h)]} · {long_map[self._long_term(h)]}"

    def _headline(self, h: _Holding, outlook: str) -> str:
        if outlook == "bullish":
            if h.change >= 0.5:
                return f"今日上漲 {h.change:.2f}%,{h.industry}買盤動能穩定,趨勢仍在軌道上。"
            return f"短線震盪,但持有至今報酬約 {h.pnl_percent:.1f}%,長線結構沒有變壞。"
        if outlook == "caution":
            if h.change <= -0.5:
                return f"今日下跌 {abs(h.change):.2f}%,{h.industry}短線賣壓較重,先觀察不急著動作。"
            return "近期走勢偏弱,短線先留意支撐,不需要急著做決定。"
        return "今日走勢平穩,沒有明顯的多空訊號,維持原本的計畫即可。"

    def _summary(self, h: _Holding, market_change: float) -> str:
        if h.change <= -0.5 and h.has_pnl and h.pnl_percent > 0:
            return "短線有獲利了結的賣壓,可能持續震盪;但你的持有成本仍有安全空間,基本面沒有變壞。"
        if h.change <= -0.5 and market_change <= -0.5:
            return "大盤同步回檔,今天的下跌比較像整體市場調節,不是這家公司單獨出事。"
        if h.change <= -0.5:
            return "今天走勢比大盤弱,短線可能還會震盪;先觀察產業消息,不用急著反應。"
        if h.change >= 0.5:
            return "今天走勢穩健偏多,市場資金仍在流入;維持既有計畫,平常心看待就好。"
        return "今天波動不大,市場在等待新的方向;對長期持有者來說是平常的一天。"

    def _signals(self, h: _Holding, market_change: float) -> List[dict]:
        direction_labels = {
            "bearish": "→ 短線偏空",
            "bullish": "→ 長線偏多",
            "neutral": "→ 中性觀望",
        }

        signals = []

        # 訊號 1:今日價格
        short = self._short_term(h)
        if short == "bearish":
            text = f"今日收盤下跌 {abs(h.change):.2f}%,短線賣壓較重,量能仍待觀察。"
        elif short == "bullish":
            text = f"今日收盤上漲 {h.change:.2f}%,買盤動能延續,短線結構偏穩。"
        else:
            text = f"今日漲跌 {h.change:+.2f}%,波動落在日常範圍內,沒有異常訊號。"
        label = "→ 短線偏空" if short == "bearish" else ("→ 短線偏多" if short == "bullish" else "→ 中性觀望")
        signals.append({
            "source": "價格 · 今天",
            "direction": short,
            "direction_label": label,
            "text": text,
        })

        # 訊號 2:與大盤對比
        diff = h.change - market_change
        if diff >= 0.5:
            direction = "bullish"
            text = f"今天大盤 {market_change:+.2f}%,這檔相對抗跌(強),顯示籌碼相對安定。"
        elif diff <= -0.5:
            direction = "bearish"
            text = f"今天大盤 {market_change:+.2f}%,這檔走勢比大盤弱,短線資金偏保守。"
        else:
            direction = "neutral"
            text = f"走勢與大盤同步({market_change:+.2f}%),屬於整體市場的正常波動。"
        signals.append({
            "source": "大盤 · 今天",
            "direction": direction,
            "direction_label": direction_labels[direction],
            "text": text,
        })

        # 訊號 3:持有成本視角
        long = self._long_term(h)
        if long == "bullish":
            text = f"以你的持有成本計算,未實現報酬約 {h.pnl_percent:+.1f}%,長線仍站在有利位置。"
        elif long == "bearish":
            text = f"目前未實現損益約 {h.pnl_percent:+.1f}%,長線偏保守;先確認產業基本面再決定。"
        elif h.has_pnl:
            text = f"未實現損益約 {h.pnl_percent:+.1f}%,接近成本區;不需要急著做任何動作。"
        else:
            text = "尚未填寫成本與股數,補上後可以看到專屬於你的長線視角。"
        long_label = "→ 長線偏多" if long == "bullish" else ("→ 長線保守" if long == "bearish" else "→ 中性觀望")
        signals.append({
            "source": "你的持倉 · 至今",
            "direction": long,
            "direction_label": long_label,
            "text": text,
        })

        return signals

    def _plain_summary(self, h: _Holding, outlook: str) -> str:
        if outlook == "caution":
            return (
                f"{h.name} 短線比較弱,但這比較像市場情緒,不是公司突然變壞。"
                "先不要盯盤,給它幾天時間,再看產業有沒有新消息。"
            )
        if outlook == "bullish":
            return (
                f"{h.name} 目前狀態不錯,趨勢還在你這邊。"
                "不需要因為漲了就改變節奏,照原本的計畫走就好。"
            )
        return (
            f"{h.name} 今天沒什麼大事,多空都在觀望。"
            "維持平常心,把注意力放回生活,比一直盯盤更有幫助。"
        )
