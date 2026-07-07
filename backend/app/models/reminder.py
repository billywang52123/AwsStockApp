from sqlalchemy import String, Boolean
from sqlalchemy.orm import Mapped, mapped_column
from app.db.database import Base

class ReminderSettingModel(Base):
    __tablename__ = "reminder_settings"

    user_id: Mapped[str] = mapped_column(String, primary_key=True, default="demo-user", index=True)
    enabled: Mapped[bool] = mapped_column(Boolean, default=True)
    time_slot: Mapped[str] = mapped_column(String, default="EVENING")
    anxiety_score: Mapped[bool] = mapped_column(Boolean, default=True)
    daily_card: Mapped[bool] = mapped_column(Boolean, default=True)
    volatility_alert: Mapped[bool] = mapped_column(Boolean, default=False)
