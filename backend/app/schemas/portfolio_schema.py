from datetime import datetime
from pydantic import BaseModel, ConfigDict
from typing import Optional

class PortfolioItemCreate(BaseModel):
    symbol: str
    cost_price: Optional[float] = None
    shares: Optional[int] = None

class PortfolioItemRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    
    id: str
    symbol: str
    name: Optional[str] = None
    cost_price: Optional[float] = None
    shares: Optional[int] = None
    created_at: datetime
