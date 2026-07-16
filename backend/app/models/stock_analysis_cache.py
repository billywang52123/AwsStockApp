from datetime import date, datetime
from sqlalchemy import String, Text, Date, DateTime, func
from sqlalchemy.orm import Mapped, mapped_column
from app.db.database import Base


class StockAnalysisCache(Base):
    """個股 AI 白話分析(/stocks/{symbol}/ai-analysis)的預算結果,
    每位使用者 × 每檔股票一列。

    有效條件與 insight_cache 相同:trade_date 等於今天、fingerprint 等於
    目前持股指紋(分析內文引用使用者持股脈絡)、provider 等於目前 AI 引擎;
    持股異動、換日或切換引擎即失效,由背景預抓逐檔重算。"""
    __tablename__ = "stock_analysis_cache"

    user_id: Mapped[str] = mapped_column(String, primary_key=True)
    symbol: Mapped[str] = mapped_column(String, primary_key=True)
    trade_date: Mapped[date] = mapped_column(Date)
    fingerprint: Mapped[str] = mapped_column(String)
    provider: Mapped[str] = mapped_column(String, default="claude")
    analysis: Mapped[str] = mapped_column(Text)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime, server_default=func.now(), onupdate=func.now()
    )
