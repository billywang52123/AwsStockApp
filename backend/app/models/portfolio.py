from datetime import datetime, timezone
from sqlalchemy import String, DateTime, Float, Integer
from sqlalchemy.orm import Mapped, mapped_column
from app.db.database import Base
import uuid

class PortfolioItem(Base):
    """One broker lot (券商分帳). A user's holding for a symbol is the set of
    active lots with that symbol; totals/avg price are aggregated at read time.
    Legacy rows (pre-lots) have broker=None and behave as a single default lot.
    """
    __tablename__ = "portfolio_items"

    id: Mapped[str] = mapped_column(String, primary_key=True, default=lambda: str(uuid.uuid4()))
    user_id: Mapped[str] = mapped_column(String, default="demo-user", index=True)
    symbol: Mapped[str] = mapped_column(String, index=True)
    cost_price: Mapped[float | None] = mapped_column(Float, nullable=True)
    shares: Mapped[int | None] = mapped_column(Integer, nullable=True)
    broker: Mapped[str | None] = mapped_column(String, nullable=True)
    # active | exited("全部賣出" soft delete, restorable from the undo toast)
    status: Mapped[str | None] = mapped_column(String, nullable=True, default="active")
    # manual | import(截圖/對帳單匯入)
    source: Mapped[str | None] = mapped_column(String, nullable=True, default="manual")
    created_at: Mapped[datetime] = mapped_column(DateTime, default=lambda: datetime.now(timezone.utc))
    updated_at: Mapped[datetime | None] = mapped_column(
        DateTime, nullable=True, default=lambda: datetime.now(timezone.utc)
    )
