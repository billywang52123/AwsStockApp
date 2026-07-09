from datetime import datetime, timezone
from sqlalchemy import String, DateTime
from sqlalchemy.orm import Mapped, mapped_column
from app.db.database import Base
import uuid


def _now() -> datetime:
    return datetime.now(timezone.utc)


class Watchlist(Base):
    """觀察清單(spec 05 · 11a–11g)。與持股嚴格分離:
    清單內股票不計入市值、損益、焦慮分數與產業曝險。"""
    __tablename__ = "watchlists"

    id: Mapped[str] = mapped_column(String, primary_key=True, default=lambda: str(uuid.uuid4()))
    user_id: Mapped[str] = mapped_column(String, default="demo-user", index=True)
    name: Mapped[str] = mapped_column(String)
    # 11b 清單顏色(5 色圓點之一,存 hex,供 11a 選單與清單頁 icon 區分清單)
    color: Mapped[str | None] = mapped_column(String, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=_now)
    updated_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True, default=_now)


class WatchlistItem(Base):
    """觀察清單內的一檔股票。轉入庫存(11d)後即從清單移除。"""
    __tablename__ = "watchlist_items"

    id: Mapped[str] = mapped_column(String, primary_key=True, default=lambda: str(uuid.uuid4()))
    user_id: Mapped[str] = mapped_column(String, default="demo-user", index=True)
    watchlist_id: Mapped[str] = mapped_column(String, index=True)
    symbol: Mapped[str] = mapped_column(String, index=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=_now)
