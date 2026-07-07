from datetime import datetime, timezone
from sqlalchemy import String, DateTime, Float, Integer
from sqlalchemy.orm import Mapped, mapped_column
from app.db.database import Base
import uuid


class HoldingActivityModel(Base):
    """持股異動紀錄(spec 04:每筆異動寫 log,9e 可回看、左滑刪除並回算)."""
    __tablename__ = "holding_activities"

    id: Mapped[str] = mapped_column(String, primary_key=True, default=lambda: str(uuid.uuid4()))
    user_id: Mapped[str] = mapped_column(String, index=True)
    symbol: Mapped[str] = mapped_column(String, index=True)
    # buy | sell | override | import | exit | restore
    activity_type: Mapped[str] = mapped_column(String)
    # Signed share change (buy +500 / sell -500); override stores the delta too
    shares_delta: Mapped[int] = mapped_column(Integer, default=0)
    price: Mapped[float | None] = mapped_column(Float, nullable=True)
    broker: Mapped[str | None] = mapped_column(String, nullable=True)
    realized_pnl: Mapped[float | None] = mapped_column(Float, nullable=True)
    # Aggregated avg price after this activity — lets deletes 回算 the reverse
    avg_price_after: Mapped[float | None] = mapped_column(Float, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=lambda: datetime.now(timezone.utc))
