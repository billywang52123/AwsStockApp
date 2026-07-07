# Import all models here so that metadata is populated correctly for migrations/scaffolding
from app.db.database import Base # noqa
# Import specific models to register metadata
from app.models.stock import Stock
from app.models.portfolio import PortfolioItem
from app.models.stock_daily_price import StockDailyPrice
from app.models.market_index import MarketIndexDaily
from app.models.reminder import ReminderSettingModel
from app.models.card_result import CardResultModel
