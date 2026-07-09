from datetime import date
from pydantic import BaseModel, ConfigDict
from typing import Optional

class StockRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    
    symbol: str
    name: str
    market: str = "TW"
    industry: Optional[str] = None

class AiScreenItem(BaseModel):
    # allow_inf_nan=False:NaN 進到回應時直接 500,而不是被序列化成 null 害 iOS 解碼失敗
    model_config = ConfigDict(allow_inf_nan=False)

    symbol: str
    name: str
    industry: Optional[str] = None
    close_price: Optional[float] = None
    change_percent: Optional[float] = None
    reason: str

class AiScreenResult(BaseModel):
    items: list[AiScreenItem]
    note: Optional[str] = None

class StockDailyPriceRead(BaseModel):
    # allow_inf_nan=False:NaN 進到回應時直接 500,而不是被序列化成 null 害 iOS 解碼失敗
    model_config = ConfigDict(from_attributes=True, allow_inf_nan=False)
    
    symbol: str
    trade_date: date
    close_price: float
    change_percent: float
    volume: Optional[float] = None
