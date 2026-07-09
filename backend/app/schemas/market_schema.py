from pydantic import BaseModel, ConfigDict

class MarketCompareResultRead(BaseModel):
    # allow_inf_nan=False:NaN 進到回應時直接 500,而不是被序列化成 null 害 iOS 解碼失敗
    model_config = ConfigDict(from_attributes=True, allow_inf_nan=False)
    
    portfolio_change_percent: float
    market_change_percent: float
    message: str
