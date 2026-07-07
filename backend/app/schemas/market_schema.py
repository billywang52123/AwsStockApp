from pydantic import BaseModel, ConfigDict

class MarketCompareResultRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    
    portfolio_change_percent: float
    market_change_percent: float
    message: str
