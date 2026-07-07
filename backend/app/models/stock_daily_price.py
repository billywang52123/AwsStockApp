from datetime import date
from sqlalchemy import String, Date, Float
from sqlalchemy.orm import Mapped, mapped_column
from app.db.database import Base

class StockDailyPrice(Base):
    __tablename__ = "stock_daily_prices"

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    symbol: Mapped[str] = mapped_column(String, index=True)
    trade_date: Mapped[date] = mapped_column(Date, index=True)
    # Float (not Numeric): PostgreSQL returns Decimal for Numeric, which breaks
    # float arithmetic in the calculators; these are display values, not ledger money
    close_price: Mapped[float] = mapped_column(Float)
    change_percent: Mapped[float] = mapped_column(Float)
    volume: Mapped[float | None] = mapped_column(Float, nullable=True)
