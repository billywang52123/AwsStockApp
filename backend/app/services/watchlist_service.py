"""觀察清單服務(spec 05 · 11a–11g)。

觀察清單與持股嚴格分離:清單內股票不計入市值、損益、焦慮分數與產業曝險;
唯一的橋樑是 11d「轉入庫存」。AI 評分只用當日價格變化規則式計算
(未持有、無成本概念),語氣沿用安撫原則,不出現買賣字眼。
"""
from typing import List, Optional

from sqlalchemy import select, and_
from sqlalchemy.orm import Session

from app.models.watchlist import Watchlist, WatchlistItem
from app.repositories.repositories import StockRepository
from app.services.holding_service import HoldingService
from app.services.services import is_finite_number
from app.services.portfolio_analysis_service import _load_holdings

OTHER_INDUSTRY = "其他"


def _clamp(value: float, low: float, high: float) -> float:
    return max(low, min(high, value))


class _WatchStock:
    """觀察清單裡的一檔股票:價格 + 規則式 AI 評分。"""

    def __init__(self, symbol: str, stock, price):
        self.symbol = symbol
        self.name = stock.name if stock else symbol
        self.industry = (stock.industry if stock and stock.industry else "") or OTHER_INDUSTRY
        self.close = float(price.close_price) if price and is_finite_number(price.close_price) else None
        self.change = float(price.change_percent) if price and is_finite_number(price.change_percent) else 0.0

        # 未持有 → 沒有成本/損益,評分只看當日動能(同 8d 規則的價格項)
        self.score = int(round(_clamp(50.0 + self.change * 6.0, 8, 92)))
        if self.score >= 60:
            self.outlook = "bullish"
        elif self.score <= 40:
            self.outlook = "caution"
        else:
            self.outlook = "neutral"

    @property
    def headline(self) -> str:
        if self.outlook == "bullish":
            return f"今日上漲 {self.change:.2f}%,{self.industry}買盤動能穩定,趨勢仍在軌道上。"
        if self.outlook == "caution":
            if self.change <= -0.5:
                return f"今日下跌 {abs(self.change):.2f}%,{self.industry}短線賣壓較重,先觀察不急著動作。"
            return "近期走勢偏弱,短線先留意支撐,不需要急著做決定。"
        return "今日走勢平穩,沒有明顯的多空訊號,持續觀察就好。"


class WatchlistService:
    def __init__(self, db: Session):
        self.db = db
        self.stock_repo = StockRepository(db)

    # ── 查詢 helpers ─────────────────────────────────────────

    def _get_list(self, user_id: str, watchlist_id: str) -> Optional[Watchlist]:
        return self.db.scalars(select(Watchlist).where(and_(
            Watchlist.id == watchlist_id, Watchlist.user_id == user_id,
        ))).first()

    def _items_of(self, user_id: str, watchlist_id: Optional[str] = None) -> List[WatchlistItem]:
        cond = [WatchlistItem.user_id == user_id]
        if watchlist_id:
            cond.append(WatchlistItem.watchlist_id == watchlist_id)
        stmt = select(WatchlistItem).where(and_(*cond)).order_by(WatchlistItem.created_at)
        return list(self.db.scalars(stmt).all())

    def _watch_stock(self, symbol: str) -> _WatchStock:
        stock = self.stock_repo.get_stock(symbol)
        price = self.stock_repo.get_daily_price(symbol)
        return _WatchStock(symbol, stock, price)

    # ── 11a / 11b · 清單 CRUD ────────────────────────────────

    def get_index(self, user_id: str) -> dict:
        holdings = _load_holdings(self.db, user_id)
        lists = self.db.scalars(
            select(Watchlist).where(Watchlist.user_id == user_id).order_by(Watchlist.created_at)
        ).all()
        return {
            "holding_count": len(holdings),
            "watchlists": [
                {
                    "id": wl.id,
                    "name": wl.name,
                    "color": wl.color,
                    "stock_count": len(self._items_of(user_id, wl.id)),
                }
                for wl in lists
            ],
        }

    def create(self, user_id: str, name: str, color: Optional[str]) -> dict:
        name = name.strip()
        if not name:
            raise ValueError("清單名稱不可為空")
        wl = Watchlist(user_id=user_id, name=name, color=color)
        self.db.add(wl)
        self.db.flush()
        return {"id": wl.id, "name": wl.name, "color": wl.color, "stock_count": 0}

    def delete(self, user_id: str, watchlist_id: str) -> bool:
        wl = self._get_list(user_id, watchlist_id)
        if wl is None:
            return False
        for item in self._items_of(user_id, watchlist_id):
            self.db.delete(item)
        self.db.delete(wl)
        self.db.flush()
        return True

    # ── 11c · 清單頁與加股 ───────────────────────────────────

    def get_detail(self, user_id: str, watchlist_id: str) -> Optional[dict]:
        wl = self._get_list(user_id, watchlist_id)
        if wl is None:
            return None
        stocks = [self._watch_stock(i.symbol) for i in self._items_of(user_id, watchlist_id)]
        stocks.sort(key=lambda s: s.score, reverse=True)
        return {
            "id": wl.id,
            "name": wl.name,
            "color": wl.color,
            "stock_count": len(stocks),
            "average_score": int(round(sum(s.score for s in stocks) / len(stocks))) if stocks else 0,
            "bullish_count": sum(1 for s in stocks if s.outlook == "bullish"),
            "neutral_count": sum(1 for s in stocks if s.outlook == "neutral"),
            "caution_count": sum(1 for s in stocks if s.outlook == "caution"),
            "items": [self._stock_dict(s) for s in stocks],
        }

    def _stock_dict(self, s: _WatchStock) -> dict:
        return {
            "symbol": s.symbol,
            "name": s.name,
            "industry": s.industry,
            "close_price": s.close,
            "change_percent": round(s.change, 2),
            "ai_score": s.score,
            "outlook": s.outlook,
            "headline": s.headline,
        }

    def add_item(self, user_id: str, watchlist_id: str, symbol: str) -> dict:
        wl = self._get_list(user_id, watchlist_id)
        if wl is None:
            raise LookupError("找不到這份觀察清單")
        if self.stock_repo.get_stock(symbol) is None:
            raise LookupError("找不到這檔股票")
        existing = [i for i in self._items_of(user_id, watchlist_id) if i.symbol == symbol]
        if not existing:
            self.db.add(WatchlistItem(user_id=user_id, watchlist_id=watchlist_id, symbol=symbol))
            self.db.flush()
        return self._stock_dict(self._watch_stock(symbol))

    def remove_item(self, user_id: str, watchlist_id: str, symbol: str) -> bool:
        removed = False
        for item in self._items_of(user_id, watchlist_id):
            if item.symbol == symbol:
                self.db.delete(item)
                removed = True
        if removed:
            self.db.flush()
        return removed

    # ── 11d · 轉入庫存 ───────────────────────────────────────

    def convert_to_holding(self, user_id: str, watchlist_id: str, symbol: str,
                           shares: int, price: Optional[float]) -> dict:
        wl = self._get_list(user_id, watchlist_id)
        if wl is None:
            raise LookupError("找不到這份觀察清單")
        if not any(i.symbol == symbol for i in self._items_of(user_id, watchlist_id)):
            raise LookupError("這檔股票不在這份觀察清單裡")

        result = HoldingService(self.db).buy(user_id, symbol, shares, price, broker=None)
        self.remove_item(user_id, watchlist_id, symbol)

        holding = result["holding"]
        stock = self.stock_repo.get_stock(symbol)
        return {
            "symbol": symbol,
            "name": stock.name if stock else symbol,
            "shares": shares,
            "watchlist_name": wl.name,
            "total_shares": holding["total_shares"] if holding else shares,
            "avg_price": holding["avg_price"] if holding else price,
        }

    # ── 11e · 觀察清單分析 ───────────────────────────────────

    def get_analysis(self, user_id: str, watchlist_id: Optional[str] = None) -> dict:
        items = self._items_of(user_id, watchlist_id)
        # 同一檔可能存在於多份清單,分析以 symbol 去重
        symbols = list(dict.fromkeys(i.symbol for i in items))
        stocks = [self._watch_stock(sym) for sym in symbols]
        if not stocks:
            return {
                "watch_count": 0, "average_score": 0,
                "trend_note": "還沒有觀察中的股票,先把想追蹤的加進清單吧。",
                "bullish_count": 0, "neutral_count": 0, "caution_count": 0,
                "exposure": [], "exposure_note": "加入觀察股後,這裡會顯示清單的產業分布。",
                "overlap_notice": None,
            }

        avg_change = sum(s.change for s in stocks) / len(stocks)
        return {
            "watch_count": len(stocks),
            "average_score": int(round(sum(s.score for s in stocks) / len(stocks))),
            "trend_note": f"清單今日平均 {avg_change:+.1f}%,整體節奏平穩" if abs(avg_change) < 1.5
            else f"清單今日平均 {avg_change:+.1f}%,波動比平常大一些",
            "bullish_count": sum(1 for s in stocks if s.outlook == "bullish"),
            "neutral_count": sum(1 for s in stocks if s.outlook == "neutral"),
            "caution_count": sum(1 for s in stocks if s.outlook == "caution"),
            "exposure": self._exposure(stocks),
            "exposure_note": self._exposure_note(stocks),
            "overlap_notice": self._overlap_notice(user_id, stocks),
        }

    def _exposure(self, stocks: List[_WatchStock]) -> List[dict]:
        """清單產業分布:未持有沒有市值權重,以檔數占比呈現(資訊陳列,非警示)。"""
        by_industry: dict = {}
        for s in stocks:
            by_industry[s.industry] = by_industry.get(s.industry, 0) + 1
        total = len(stocks)
        segments = [
            {"industry": industry, "percent": round(count / total * 100.0, 1)}
            for industry, count in by_industry.items()
        ]
        segments.sort(key=lambda seg: seg["percent"], reverse=True)
        return segments

    def _exposure_note(self, stocks: List[_WatchStock]) -> str:
        segments = self._exposure(stocks)
        top = segments[0]
        if len(segments) == 1:
            return f"清單集中在{top['industry']},之後想分散可以再加入不同產業。"
        return f"清單以{top['industry']}為主({top['percent']:.0f}%),分布單純、方便追蹤。"

    def _overlap_notice(self, user_id: str, stocks: List[_WatchStock]) -> Optional[dict]:
        """與庫存重疊提醒:試算「若全部各轉入一張」後,重疊產業的曝險變化。"""
        holdings = _load_holdings(self.db, user_id)
        if not holdings:
            return None

        current_total = sum(h.market_value for h in holdings)
        if current_total <= 0:
            return None

        by_industry: dict = {}
        for h in holdings:
            by_industry[h.industry] = by_industry.get(h.industry, 0.0) + h.market_value

        # 假設每檔觀察股各轉入 1 張(1,000 股)現價
        added: dict = {}
        for s in stocks:
            if s.close is None:
                continue
            added[s.industry] = added.get(s.industry, 0.0) + s.close * 1000

        overlap = [ind for ind in added if ind in by_industry]
        if not overlap or not added:
            return None

        new_total = current_total + sum(added.values())
        # 取變化最大的重疊產業來提醒
        def _delta(ind: str) -> float:
            before = by_industry[ind] / current_total * 100.0
            after = (by_industry[ind] + added.get(ind, 0.0)) / new_total * 100.0
            return after - before

        top = max(overlap, key=lambda ind: abs(_delta(ind)))
        before_pct = by_industry[top] / current_total * 100.0
        after_pct = (by_industry[top] + added.get(top, 0.0)) / new_total * 100.0
        highlight = f"{before_pct:.0f}% → {after_pct:.0f}%"

        return {
            "title": "與你的庫存重疊提醒",
            "body": f"清單裡有{top}股票,與你目前的庫存重疊。若全部各轉入一張,"
                    f"{top}曝險約從 {highlight}。",
            "highlight": highlight,
            "plain_talk": f"白話說:你已經持有{top}的股票了,觀察清單裡又有同產業的,"
                          f"之後轉入時可以留意集中度。",
        }

    # ── 11f · 觀點分頁 ───────────────────────────────────────

    def get_insights(self, user_id: str) -> dict:
        lists = {wl.id: wl.name for wl in self.db.scalars(
            select(Watchlist).where(Watchlist.user_id == user_id)
        ).all()}
        entries = []
        for item in self._items_of(user_id):
            s = self._watch_stock(item.symbol)
            entries.append((s, lists.get(item.watchlist_id, "觀察清單")))
        entries.sort(key=lambda e: e[0].score, reverse=True)

        items = [
            {
                "symbol": s.symbol,
                "name": s.name,
                "industry": s.industry,
                "watchlist_name": list_name,
                "ai_score": s.score,
                "outlook": s.outlook,
                "headline": s.headline,
            }
            for s, list_name in entries
        ]
        return {
            "bullish_count": sum(1 for i in items if i["outlook"] == "bullish"),
            "neutral_count": sum(1 for i in items if i["outlook"] == "neutral"),
            "caution_count": sum(1 for i in items if i["outlook"] == "caution"),
            "items": items,
        }

    # ── 11g · 推薦星標 ───────────────────────────────────────

    def membership_map(self, user_id: str) -> dict:
        """symbol → (watchlist_id, watchlist_name),供推薦卡疊星標與狀態 pill。"""
        lists = {wl.id: wl.name for wl in self.db.scalars(
            select(Watchlist).where(Watchlist.user_id == user_id)
        ).all()}
        mapping: dict = {}
        for item in self._items_of(user_id):
            mapping.setdefault(item.symbol, (item.watchlist_id, lists.get(item.watchlist_id, "觀察清單")))
        return mapping
