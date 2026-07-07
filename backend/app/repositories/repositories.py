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
        stmt = select(StockDailyPrice).where(StockDailyPrice.symbol == symbol).order_by(StockDailyPrice.trade_date.desc())
        return self.db.scalars(stmt).first()

class PortfolioRepository:
    def __init__(self, db: Session):
        self.db = db
        
    def get_items(self, user_id: str = "demo-user") -> List[PortfolioItem]:
        stmt = select(PortfolioItem).where(PortfolioItem.user_id == user_id)
        return list(self.db.scalars(stmt).all())
        
    def add_item(self, item: PortfolioItem) -> PortfolioItem:
        stmt = select(PortfolioItem).where(
            and_(PortfolioItem.user_id == item.user_id, PortfolioItem.symbol == item.symbol)
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
