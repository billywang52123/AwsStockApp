import datetime as _dt
from typing import Optional
from pydantic import BaseModel, Field


class SimDateStatus(BaseModel):
    """模擬時鐘目前狀態。"""
    overridden: bool = Field(..., description="是否有手動覆寫模擬今天")
    effective_today: _dt.date = Field(..., description="全 App 目前採用的『今天』")
    simulated_trade_date: _dt.date = Field(..., description="模擬交易日目標 = 今天 − 1 年")
    resolved_data_date: Optional[_dt.date] = Field(
        None, description="CMoney 實際有資料的最近交易日(假日/無資料會回退)"
    )
    data_available: bool = Field(..., description="CMoney raw 資料是否可用")


class SimDateUpdate(BaseModel):
    """設定模擬今天。傳想模擬的『真實今天』日期,模擬交易日會是它減一年。"""
    date: _dt.date = Field(..., description="要模擬的今天日期,例如 2026-03-15")
