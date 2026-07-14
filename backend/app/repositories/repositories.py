from sqlalchemy.orm import Session
from sqlalchemy import select, delete, and_
from app.models.stock import Stock
from app.models.portfolio import PortfolioItem
from app.models.stock_daily_price import StockDailyPrice
from app.models.market_index import MarketIndexDaily
from app.models.reminder import ReminderSettingModel
from app.models.card_result import CardResultModel
from datetime import date
from typing import List, Optional

class StockRepository:
    def __init__(self, db: Session):
        self.db = db
        
    def search_stocks(self, keyword: str) -> List[Stock]:
        if not keyword:
            stmt = select(Stock)
        else:
            stmt = select(Stock).where(
                Stock.symbol.contains(keyword) | 
                Stock.name.contains(keyword)
            )
        return list(self.db.scalars(stmt).all())
        
    def get_stock(self, symbol: str) -> Optional[Stock]:
        stmt = select(Stock).where(Stock.symbol == symbol)
        return self.db.scalars(stmt).first()

    def get_daily_price(self, symbol: str) -> Optional[StockDailyPrice]:
        stmt = select(StockDailyPrice).where(StockDailyPrice.symbol == symbol)
        # 模擬時鐘覆寫到過去時,把上限鎖在「有效今天」,不讓較晚日期的舊列(未來價)外洩。
        # 未覆寫時維持原行為(回最新一筆),避免與測試/正常時序耦合。
        from app.services import sim_clock
        override = sim_clock.get_override()
        if override is not None:
            stmt = stmt.where(StockDailyPrice.trade_date <= override)
        stmt = stmt.order_by(StockDailyPrice.trade_date.desc())
        return self.db.scalars(stmt).first()

class PortfolioRepository:
    def __init__(self, db: Session):
        self.db = db
        
    def get_items(self, user_id: str = "demo-user") -> List[PortfolioItem]:
        stmt = select(PortfolioItem).where(PortfolioItem.user_id == user_id)
        return list(self.db.scalars(stmt).all())
        
    def add_item(self, item: PortfolioItem) -> PortfolioItem:
        # 冪等判斷只看「未清倉」的列:同檔全部賣出(status=exited)後重新加入,
        # 要建新的 active 列;回傳被隱藏的清倉列會讓「新增持股」看起來沒反應
        stmt = select(PortfolioItem).where(
            and_(
                PortfolioItem.user_id == item.user_id,
                PortfolioItem.symbol == item.symbol,
                (PortfolioItem.status.is_(None)) | (PortfolioItem.status != "exited"),
            )
        )
        existing = self.db.scalars(stmt).first()
        if existing:
            return existing
        self.db.add(item)
        self.db.flush()
        self.db.refresh(item)
        return item
        
    def delete_item(self, item_id: str, user_id: str = "demo-user") -> bool:
        stmt = delete(PortfolioItem).where(
            and_(PortfolioItem.id == item_id, PortfolioItem.user_id == user_id)
        )
        res = self.db.execute(stmt)
        return res.rowcount > 0

class CardRepository:
    def __init__(self, db: Session):
        self.db = db
        
    def get_today_card(self, user_id: str = "demo-user", trade_date: Optional[date] = None) -> Optional[CardResultModel]:
        if not trade_date:
            trade_date = date.today()
        stmt = select(CardResultModel).where(
            and_(CardResultModel.user_id == user_id, CardResultModel.trade_date == trade_date)
        )
        return self.db.scalars(stmt).first()
        
    def save_card(self, card: CardResultModel) -> CardResultModel:
        self.db.add(card)
        self.db.flush()
        self.db.refresh(card)
        return card

class ReminderRepository:
    def __init__(self, db: Session):
        self.db = db
        
    def get_settings(self, user_id: str = "demo-user") -> ReminderSettingModel:
        stmt = select(ReminderSettingModel).where(ReminderSettingModel.user_id == user_id)
        setting = self.db.scalars(stmt).first()
        if not setting:
            setting = ReminderSettingModel(user_id=user_id)
            self.db.add(setting)
            self.db.flush()
            self.db.refresh(setting)
        return setting
        
    def save_settings(self, user_id: str, enabled: bool, time_slot: str, anxiety_score: bool, daily_card: bool, volatility_alert: bool) -> ReminderSettingModel:
        setting = self.get_settings(user_id)
        setting.enabled = enabled
        setting.time_slot = time_slot
        setting.anxiety_score = anxiety_score
        setting.daily_card = daily_card
        setting.volatility_alert = volatility_alert
        self.db.add(setting)
        self.db.flush()
        self.db.refresh(setting)
        return setting

class MarketIndexRepository:
    def __init__(self, db: Session):
        self.db = db
        
    def get_latest_index(self, index_code: str = "TAIEX") -> Optional[MarketIndexDaily]:
        stmt = select(MarketIndexDaily).where(MarketIndexDaily.index_code == index_code).order_by(MarketIndexDaily.trade_date.desc())
        return self.db.scalars(stmt).first()
