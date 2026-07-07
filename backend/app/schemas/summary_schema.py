from pydantic import BaseModel, ConfigDict
from typing import Literal

class PortfolioImpactItemRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    
    symbol: str
    name: str
    change_percent: float
    impact_level: Literal["HIGH", "MEDIUM", "LOW"]
    reason: str

class DailySummaryRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    
    title: str
    summary: str
    explanation: str
    portfolio_impact_items: list[PortfolioImpactItemRead]
    disclaimer: str
