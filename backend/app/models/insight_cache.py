from datetime import date, datetime
from sqlalchemy import String, Text, Date, DateTime, func
from sqlalchemy.orm import Mapped, mapped_column
from app.db.database import Base


class InsightCache(Base):
    """每位使用者一列的 /insights 預算結果(AgentCore 很慢,先算好存起來)。

    有效條件:trade_date 等於今天(14:30 換日)、fingerprint 等於目前持股指紋、
    且 provider 等於使用者目前選的 AI 引擎(claude/openai,內容不同不可混用);
    持股異動、換日或切換引擎即自動失效,由背景預抓重算。"""
    __tablename__ = "insight_cache"

    user_id: Mapped[str] = mapped_column(String, primary_key=True)
    trade_date: Mapped[date] = mapped_column(Date)
    fingerprint: Mapped[str] = mapped_column(String)
    provider: Mapped[str] = mapped_column(String, default="claude")
    payload: Mapped[str] = mapped_column(Text)  # InsightListRead JSON
    updated_at: Mapped[datetime] = mapped_column(
        DateTime, server_default=func.now(), onupdate=func.now()
    )
