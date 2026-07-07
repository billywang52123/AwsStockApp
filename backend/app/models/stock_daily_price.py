from datetime import date
from sqlalchemy import String, Date, Numeric
from sqlalchemy.orm import Mapped, mapped_column
from app.db.database import Base

class StockDailyPrice(Base):
    __tablename__ = "stock_daily_prices"

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    symbol: Mapped[str] = mapped_column(String, index=True)
    trade_date: Mapped[date] = mapped_column(Date, index=True)
    close_price: Mapped[float] = mapped_column(Numeric)
    change_percent: Mapped[float] = mapped_column(Numeric)
    volume: Mapped[float | None] = mapped_column(Numeric, nullable=True)
