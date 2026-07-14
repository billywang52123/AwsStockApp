from datetime import datetime
from pydantic import BaseModel, ConfigDict, Field
from typing import Optional

class PortfolioItemCreate(BaseModel):
    # allow_inf_nan=False:JSON 的 NaN/Infinity 在進門時就 422,不讓壞數字進 DB
    # (上限只是防呆:單價一千萬、十億股,正常資料碰不到)
    model_config = ConfigDict(allow_inf_nan=False)

    symbol: str
    cost_price: Optional[float] = Field(default=None, ge=0, le=10_000_000)
    shares: Optional[int] = Field(default=None, ge=0, le=1_000_000_000)
    broker: Optional[str] = None

class PortfolioItemRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: str
    symbol: str
    name: Optional[str] = None
    cost_price: Optional[float] = None
    shares: Optional[int] = None
    broker: Optional[str] = None
    created_at: datetime
