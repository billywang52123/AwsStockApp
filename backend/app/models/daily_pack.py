from datetime import date
from sqlalchemy import String, Date, Text, Boolean
from sqlalchemy.orm import Mapped, mapped_column
from app.db.database import Base


class DailyPackModel(Base):
    """每日抽卡包(spec 06 · 15a–15k,取代御神籤)。

    每人每交易日一包;整包內容(事實/推論/陪伴三卡 + 出處 chips + 對帳 claims)
    以 JSON 字串存,當日重複請求直接回存檔,確保內容全天一致。
    claims 供 15k 週末體檢對帳:說中沒說中都照實呈現。"""
    __tablename__ = "daily_packs"

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    user_id: Mapped[str] = mapped_column(String, default="demo-user", index=True)
    trade_date: Mapped[date] = mapped_column(Date, index=True)
    opened: Mapped[bool] = mapped_column(Boolean, default=False)   # 開包動畫看完(或跳過)後標記
    pack_json: Mapped[str] = mapped_column(Text, nullable=False)
