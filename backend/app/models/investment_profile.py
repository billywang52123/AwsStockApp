"""使用者投資風格問卷與持股習慣歷史。"""

import uuid
from datetime import datetime, timezone

from sqlalchemy import DateTime, Integer, String, Text
from sqlalchemy.orm import Mapped, mapped_column

from app.db.database import Base


def _utcnow() -> datetime:
    return datetime.now(timezone.utc).replace(tzinfo=None)


class InvestmentProfileModel(Base):
    __tablename__ = "investment_profiles"

    # 一個匿名/登入使用者只有一份目前問卷結果。
    user_id: Mapped[str] = mapped_column(String, primary_key=True)
    questionnaire_version: Mapped[int] = mapped_column(Integer, default=1)
    answers_json: Mapped[str] = mapped_column(Text, default="{}")
    preference_style_code: Mapped[str] = mapped_column(String)
    preference_style_label: Mapped[str] = mapped_column(String)
    preference_style_summary: Mapped[str] = mapped_column(Text)
    dimension_scores_json: Mapped[str] = mapped_column(Text, default="{}")
    completed_at: Mapped[datetime] = mapped_column(DateTime, default=_utcnow)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=_utcnow, onupdate=_utcnow)


class InvestmentHabitSnapshotModel(Base):
    __tablename__ = "investment_habit_snapshots"

    id: Mapped[str] = mapped_column(String, primary_key=True, default=lambda: str(uuid.uuid4()))
    user_id: Mapped[str] = mapped_column(String, index=True)
    trigger: Mapped[str] = mapped_column(String)
    preference_style_code: Mapped[str] = mapped_column(String)
    observed_style_code: Mapped[str] = mapped_column(String)
    observed_style_label: Mapped[str] = mapped_column(String)
    observed_style_summary: Mapped[str] = mapped_column(Text)
    habit_code: Mapped[str] = mapped_column(String)
    habit_label: Mapped[str] = mapped_column(String)
    habit_summary: Mapped[str] = mapped_column(Text)
    metrics_json: Mapped[str] = mapped_column(Text, default="{}")
    change_summary: Mapped[str] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=_utcnow, index=True)
