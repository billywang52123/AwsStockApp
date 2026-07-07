from datetime import date
from sqlalchemy import String, Date
from sqlalchemy.orm import Mapped, mapped_column
from app.db.database import Base

class CardResultModel(Base):
    __tablename__ = "card_results"

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    user_id: Mapped[str] = mapped_column(String, default="demo-user", index=True)
    trade_date: Mapped[date] = mapped_column(Date, index=True)
    card_type: Mapped[str] = mapped_column(String, nullable=False)
    title: Mapped[str] = mapped_column(String, nullable=False)
    message: Mapped[str] = mapped_column(String, nullable=False)
    action_text: Mapped[str] = mapped_column(String, nullable=False)
