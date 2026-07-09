from pydantic import BaseModel, ConfigDict
from typing import Literal

class PortfolioImpactItemRead(BaseModel):
    # allow_inf_nan=False:NaN 進到回應時直接 500,而不是被序列化成 null 害 iOS 解碼失敗
    model_config = ConfigDict(from_attributes=True, allow_inf_nan=False)
    
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
