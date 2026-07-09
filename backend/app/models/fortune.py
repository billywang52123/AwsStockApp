from datetime import date
from sqlalchemy import String, Date, Integer, Text
from sqlalchemy.orm import Mapped, mapped_column
from app.db.database import Base


class FortuneResultModel(Base):
    """每日御神籤(spec 第十輪 12a–12d)。每人每天一支,收盤後更新。

    三欄位內容(持股與狀態 / 說明 / 注意事項)以 JSON 字串存,
    當天重複請求直接回存檔,確保籤詩全天一致。"""
    __tablename__ = "fortune_results"

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    user_id: Mapped[str] = mapped_column(String, default="demo-user", index=True)
    trade_date: Mapped[date] = mapped_column(Date, index=True)
    stick_number: Mapped[int] = mapped_column(Integer, nullable=False)     # 第 N 籤(1–100)
    overall_level: Mapped[str] = mapped_column(String, nullable=False)     # 六級:大吉/吉/小吉/小凶/凶/大凶
    level_note: Mapped[str] = mapped_column(String, nullable=False)        # 籤等一句話(12d 語氣)
    holdings_json: Mapped[str] = mapped_column(Text, nullable=False)       # 持股與狀態
    summary: Mapped[str] = mapped_column(Text, nullable=False)             # 說明:可能發生的事
    stance: Mapped[str] = mapped_column(String, nullable=False)            # 今天的節奏(偏向觀望…)
    stance_note: Mapped[str] = mapped_column(String, nullable=False)
    notices_json: Mapped[str] = mapped_column(Text, nullable=False)        # 注意事項
