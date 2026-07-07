from datetime import datetime, timezone
from sqlalchemy import String, DateTime, Float, Integer
from sqlalchemy.orm import Mapped, mapped_column
from app.db.database import Base
import uuid

class PortfolioItem(Base):
    __tablename__ = "portfolio_items"

    id: Mapped[str] = mapped_column(String, primary_key=True, default=lambda: str(uuid.uuid4()))
    user_id: Mapped[str] = mapped_column(String, default="demo-user", index=True)
    symbol: Mapped[str] = mapped_column(String, index=True)
    cost_price: Mapped[float | None] = mapped_column(Float, nullable=True)
    shares: Mapped[int | None] = mapped_column(Integer, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=lambda: datetime.now(timezone.utc))
