from datetime import date
from pydantic import BaseModel, ConfigDict
from typing import Optional

class StockRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    
    symbol: str
    name: str
    market: str = "TW"
    industry: Optional[str] = None

class StockDailyPriceRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    
    symbol: str
    trade_date: date
    close_price: float
    change_percent: float
    volume: Optional[float] = None
