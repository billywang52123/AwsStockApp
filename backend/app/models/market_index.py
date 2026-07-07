from datetime import date
from sqlalchemy import String, Date, Numeric
from sqlalchemy.orm import Mapped, mapped_column
from app.db.database import Base

class MarketIndexDaily(Base):
    __tablename__ = "market_index_daily"

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    index_code: Mapped[str] = mapped_column(String, default="TAIEX", index=True)
    trade_date: Mapped[date] = mapped_column(Date, index=True)
    close_price: Mapped[float] = mapped_column(Numeric)
    change_percent: Mapped[float] = mapped_column(Numeric)
