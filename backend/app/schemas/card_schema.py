from pydantic import BaseModel, ConfigDict
from typing import Literal

class DrawCardResultRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    
    card_type: Literal[
        "CALM_OBSERVE",
        "MARKET_IMPACT",
        "VOLATILITY_ALERT",
        "STOCK_EVENT",
        "CONFIDENCE_RESTORE"
    ]
    title: str
    message: str
    action_text: str
