"""持股異動與多券商合併(spec 04 · 9a–9e 的後端實作).

規則對照 docs/uiux/specs/04 的「合併與均價計算規則」表:
- 加碼:新均價 = (舊股數×舊均價 + 新股數×買價) ÷ 總股數,四捨五入至 0.1
- 加碼未填買價:只加股數、均價不變,持股標記 avg_price_incomplete
- 賣出:股數減少、均價不變;已實現損益 = (賣價 − 均價) × 股數
- 全部賣出:soft delete(status=exited),可還原
- 覆蓋:總股數取代、均價保留
- 匯入:同券商 → 取代該分帳 / 不同券商 → 新分帳加總;無均價分帳不計入加權
- 每筆異動寫 HoldingActivity,可刪除並回算
"""

from datetime import datetime, timezone
from typing import List, Optional

from sqlalchemy import select, and_
from sqlalchemy.orm import Session

from app.models.portfolio import PortfolioItem
from app.models.holding_activity import HoldingActivityModel
from app.models.stock import Stock


def _now() -> datetime:
    return datetime.now(timezone.utc)


def weighted_average(pairs: List[tuple]) -> Optional[float]:
    """(shares, price) 加權均價,捨入至 0.1;沒有可加權的分帳時回 None."""
    total = sum(s for s, p in pairs if s and p is not None)
    if total <= 0:
        return None
    value = sum(s * p for s, p in pairs if s and p is not None)
    return round(value / total, 1)


class HoldingService:
    def __init__(self, db: Session):
        self.db = db

    # ---- queries -----------------------------------------------------------

    def _active_lots(self, user_id: str, symbol: Optional[str] = None) -> List[PortfolioItem]:
        cond = [
            PortfolioItem.user_id == user_id,
            (PortfolioItem.status.is_(None)) | (PortfolioItem.status != "exited"),
        ]
        if symbol:
            cond.append(PortfolioItem.symbol == symbol)
        stmt = select(PortfolioItem).where(and_(*cond)).order_by(PortfolioItem.created_at)
        return list(self.db.scalars(stmt).all())

    def _stock_meta(self, symbol: str) -> tuple:
        stock = self.db.scalars(select(Stock).where(Stock.symbol == symbol)).first()
        return (stock.name if stock else symbol, stock.industry if stock else None)

    def _holding_dict(self, symbol: str, lots: List[PortfolioItem]) -> dict:
        name, industry = self._stock_meta(symbol)
        total_shares = sum(l.shares or 0 for l in lots)
        avg = weighted_average([(l.shares or 0, l.cost_price) for l in lots])
        incomplete = any((l.shares or 0) > 0 and l.cost_price is None for l in lots)
        return {
            "symbol": symbol,
            "name": name,
            "industry": industry,
            "total_shares": total_shares,
            "avg_price": avg,
            "avg_price_incomplete": incomplete,
            "lots": [
                {
                    "id": l.id,
                    "broker": l.broker,
                    "shares": l.shares or 0,
                    "avg_price": l.cost_price,
                    "source": l.source or "manual",
                    "created_at": l.created_at,
                    "updated_at": l.updated_at or l.created_at,
                }
                for l in lots
            ],
        }

    def get_holdings(self, user_id: str) -> List[dict]:
        by_symbol: dict = {}
        for lot in self._active_lots(user_id):
            by_symbol.setdefault(lot.symbol, []).append(lot)
        return [self._holding_dict(sym, lots) for sym, lots in by_symbol.items()]

    def get_holding(self, user_id: str, symbol: str) -> Optional[dict]:
        lots = self._active_lots(user_id, symbol)
        if not lots:
            return None
        return self._holding_dict(symbol, lots)

    # ---- activity log ------------------------------------------------------

    def _log(self, user_id: str, symbol: str, activity_type: str, shares_delta: int,
             price: Optional[float], broker: Optional[str],
             realized_pnl: Optional[float] = None) -> None:
        holding = self.get_holding(user_id, symbol)
        self.db.add(HoldingActivityModel(
            user_id=user_id,
            symbol=symbol,
            activity_type=activity_type,
            shares_delta=shares_delta,
            price=price,
            broker=broker,
            realized_pnl=realized_pnl,
            avg_price_after=holding["avg_price"] if holding else None,
        ))
        self.db.flush()

    def get_activities(self, user_id: str, symbol: str) -> List[dict]:
        stmt = (
            select(HoldingActivityModel)
            .where(and_(HoldingActivityModel.user_id == user_id,
                        HoldingActivityModel.symbol == symbol))
            .order_by(HoldingActivityModel.created_at.desc())
            .limit(50)
        )
        return [
            {
                "id": a.id,
                "symbol": a.symbol,
                "activity_type": a.activity_type,
                "shares_delta": a.shares_delta,
                "price": a.price,
                "broker": a.broker,
                "realized_pnl": a.realized_pnl,
                "avg_price_after": a.avg_price_after,
                "created_at": a.created_at,
            }
            for a in self.db.scalars(stmt).all()
        ]

    def delete_activity(self, user_id: str, activity_id: str) -> bool:
        """左滑刪除異動:買/賣可回算(反向套用股數與均價),其餘僅刪紀錄."""
        activity = self.db.scalars(select(HoldingActivityModel).where(and_(
            HoldingActivityModel.id == activity_id,
            HoldingActivityModel.user_id == user_id,
        ))).first()
        if not activity:
            return False

        lots = self._active_lots(user_id, activity.symbol)
        if lots and activity.activity_type in ("buy", "sell") and activity.shares_delta:
            target = next((l for l in lots if l.broker == activity.broker), lots[0])
            reversed_shares = (target.shares or 0) - activity.shares_delta
            if reversed_shares >= 0:
                if (activity.activity_type == "buy" and activity.price is not None
                        and target.cost_price is not None):
                    # 反向攤平:回推加碼前均價
                    old_value = (target.shares or 0) * target.cost_price - activity.shares_delta * activity.price
                    target.cost_price = (
                        round(old_value / reversed_shares, 1) if reversed_shares > 0 else None
                    )
                target.shares = reversed_shares
                target.updated_at = _now()

        self.db.delete(activity)
        self.db.flush()
        return True

    # ---- lot helpers -------------------------------------------------------

    def _find_lot(self, lots: List[PortfolioItem], broker: Optional[str]) -> Optional[PortfolioItem]:
        """指定券商找該分帳;未指定且僅一個分帳時直接用它."""
        if broker:
            return next((l for l in lots if l.broker == broker), None)
        if len(lots) == 1:
            return lots[0]
        return next((l for l in lots if l.broker is None), None)

    def _create_lot(self, user_id: str, symbol: str, shares: int,
                    cost_price: Optional[float], broker: Optional[str],
                    source: str = "manual") -> PortfolioItem:
        lot = PortfolioItem(
            user_id=user_id, symbol=symbol, shares=shares, cost_price=cost_price,
            broker=broker, status="active", source=source, updated_at=_now(),
        )
        self.db.add(lot)
        self.db.flush()
        return lot

    # ---- 9b 加碼 -----------------------------------------------------------

    def buy(self, user_id: str, symbol: str, shares: int,
            price: Optional[float], broker: Optional[str]) -> dict:
        if shares <= 0:
            raise ValueError("股數需大於 0")
        lots = self._active_lots(user_id, symbol)
        lot = self._find_lot(lots, broker)
        if lot is None:
            lot = self._create_lot(user_id, symbol, 0, None, broker)

        old_shares = lot.shares or 0
        new_shares = old_shares + shares
        if price is not None:
            # 攤平:忽略沒有均價的舊部位(spec:無均價不計入加權)
            pairs = [(old_shares, lot.cost_price), (shares, price)]
            lot.cost_price = weighted_average(pairs)
        # price 為 None → 僅更新股數,均價不變(avg_price_incomplete 由聚合層判斷)
        lot.shares = new_shares
        lot.updated_at = _now()
        self.db.flush()

        self._log(user_id, symbol, "buy", shares, price, lot.broker)
        return {"holding": self.get_holding(user_id, symbol), "realized_pnl": None,
                "realized_pnl_percent": None, "exited": False}

    # ---- 9c 賣出 -----------------------------------------------------------

    def sell(self, user_id: str, symbol: str, shares: int,
             price: Optional[float], broker: Optional[str]) -> dict:
        if shares <= 0:
            raise ValueError("股數需大於 0")
        lots = self._active_lots(user_id, symbol)
        if not lots:
            raise LookupError("找不到這檔持股")
        total = sum(l.shares or 0 for l in lots)
        if shares > total:
            raise ValueError("賣出股數超過持有股數")

        avg_before = weighted_average([(l.shares or 0, l.cost_price) for l in lots])
        realized = None
        realized_pct = None
        if price is not None and avg_before is not None:
            realized = round((price - avg_before) * shares, 0)
            realized_pct = round((price - avg_before) / avg_before * 100, 1) if avg_before else None

        # 指定券商從該分帳扣,否則由舊到新依序扣(均價不變)
        remaining = shares
        targets = [l for l in lots if l.broker == broker] if broker else lots
        if broker and not targets:
            raise LookupError("找不到該券商分帳")
        for lot in targets:
            if remaining <= 0:
                break
            take = min(lot.shares or 0, remaining)
            lot.shares = (lot.shares or 0) - take
            lot.updated_at = _now()
            remaining -= take
        if remaining > 0:
            raise ValueError("該券商分帳股數不足")

        exited = all((l.shares or 0) == 0 for l in lots)
        self._log(user_id, symbol, "sell", -shares, price, broker, realized_pnl=realized)
        if exited:
            # 全部賣出 → 移到已出場(soft delete,undo toast 可還原)
            for lot in lots:
                lot.status = "exited"
                lot.updated_at = _now()
            self._log(user_id, symbol, "exit", 0, price, broker)
        self.db.flush()

        return {"holding": self.get_holding(user_id, symbol),
                "realized_pnl": realized, "realized_pnl_percent": realized_pct,
                "exited": exited}

    def restore(self, user_id: str, symbol: str) -> dict:
        """還原「全部賣出」:把 exited 分帳復原成賣出前的股數."""
        stmt = select(PortfolioItem).where(and_(
            PortfolioItem.user_id == user_id,
            PortfolioItem.symbol == symbol,
            PortfolioItem.status == "exited",
        ))
        lots = list(self.db.scalars(stmt).all())
        if not lots:
            raise LookupError("沒有可還原的持股")
        for lot in lots:
            lot.status = "active"
            lot.updated_at = _now()
        # 拿掉這次 exit 與 sell 的紀錄並補回股數
        acts = self.db.scalars(
            select(HoldingActivityModel)
            .where(and_(HoldingActivityModel.user_id == user_id,
                        HoldingActivityModel.symbol == symbol))
            .order_by(HoldingActivityModel.created_at.desc())
            .limit(2)
        ).all()
        for act in acts:
            if act.activity_type == "exit":
                self.db.delete(act)
            elif act.activity_type == "sell":
                target = self._find_lot(lots, act.broker) or lots[0]
                target.shares = (target.shares or 0) - act.shares_delta  # delta 為負
                self.db.delete(act)
        self._log(user_id, symbol, "restore", 0, None, None)
        self.db.flush()
        return {"holding": self.get_holding(user_id, symbol), "realized_pnl": None,
                "realized_pnl_percent": None, "exited": False}

    # ---- 覆蓋為最新庫存 ------------------------------------------------------

    def override(self, user_id: str, symbol: str, shares: int,
                 broker: Optional[str]) -> dict:
        """總股數取代、均價保留;多分帳未指定券商時按占比縮放."""
        if shares < 0:
            raise ValueError("股數不可為負")
        lots = self._active_lots(user_id, symbol)
        if not lots:
            raise LookupError("找不到這檔持股")

        old_total = sum(l.shares or 0 for l in lots)
        if broker or len(lots) == 1:
            lot = self._find_lot(lots, broker)
            if lot is None:
                raise LookupError("找不到該券商分帳")
            lot.shares = shares
            lot.updated_at = _now()
        else:
            # 依原占比縮放,尾差補到最大分帳,維持分帳結構
            scale = (shares / old_total) if old_total else 0
            assigned = 0
            for lot in lots:
                lot.shares = int((lot.shares or 0) * scale)
                lot.updated_at = _now()
                assigned += lot.shares
            largest = max(lots, key=lambda l: l.shares or 0)
            largest.shares = (largest.shares or 0) + (shares - assigned)

        new_total = sum(l.shares or 0 for l in lots)
        self._log(user_id, symbol, "override", new_total - old_total, None, broker)
        self.db.flush()
        return {"holding": self.get_holding(user_id, symbol), "realized_pnl": None,
                "realized_pnl_percent": None, "exited": False}

    # ---- 9d 匯入合併 --------------------------------------------------------

    def import_merge(self, user_id: str, decisions: List[dict]) -> dict:
        """套用匯入合併決策.

        action:
        - add_lot        不同券商 → 建立新分帳(總覽自動加權)
        - replace_broker 同券商視為最新快照 → 取代該券商分帳
        - merge_add      與該券商分帳加總攤平
        - replace_all    取代全部:刪除該檔其他分帳
        - skip           略過
        """
        updated_symbols: List[str] = []
        for d in decisions:
            action = d.get("action", "skip")
            if action == "skip":
                continue
            symbol = d["symbol"]
            shares = int(d.get("shares") or 0)
            cost = d.get("cost")
            broker = d.get("broker")
            if shares <= 0:
                continue

            lots = self._active_lots(user_id, symbol)

            if action == "replace_all":
                for lot in lots:
                    self.db.delete(lot)
                self.db.flush()
                self._create_lot(user_id, symbol, shares, cost, broker, source="import")
            elif action == "replace_broker":
                lot = self._find_lot(lots, broker)
                if lot is None:
                    self._create_lot(user_id, symbol, shares, cost, broker, source="import")
                else:
                    lot.shares = shares
                    lot.cost_price = cost
                    lot.broker = broker or lot.broker
                    lot.source = "import"
                    lot.updated_at = _now()
            elif action == "merge_add":
                lot = self._find_lot(lots, broker)
                if lot is None:
                    self._create_lot(user_id, symbol, shares, cost, broker, source="import")
                else:
                    if cost is not None:
                        lot.cost_price = weighted_average(
                            [(lot.shares or 0, lot.cost_price), (shares, cost)]
                        )
                    lot.shares = (lot.shares or 0) + shares
                    lot.source = "import"
                    lot.updated_at = _now()
            else:  # add_lot(含全新持股)
                existing = next((l for l in lots if l.broker == broker), None) if broker else None
                if existing:
                    # 同券商重複匯入視為最新快照
                    existing.shares = shares
                    existing.cost_price = cost
                    existing.source = "import"
                    existing.updated_at = _now()
                else:
                    self._create_lot(user_id, symbol, shares, cost, broker, source="import")

            self.db.flush()
            self._log(user_id, symbol, "import", shares, cost, broker)
            updated_symbols.append(symbol)

        holdings = [h for h in (self.get_holding(user_id, s) for s in dict.fromkeys(updated_symbols)) if h]
        return {"updated_count": len(dict.fromkeys(updated_symbols)), "holdings": holdings}
