from sqlalchemy import String
from sqlalchemy.orm import Mapped, mapped_column
from app.db.database import Base

class Stock(Base):
    __tablename__ = "stocks"

    symbol: Mapped[str] = mapped_column(String, primary_key=True, index=True)
    name: Mapped[str] = mapped_column(String, nullable=False)
    market: Mapped[str] = mapped_column(String, default="TW")
    industry: Mapped[str] = mapped_column(String, default="")
