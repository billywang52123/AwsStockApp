from pydantic import BaseModel, ConfigDict
from typing import Literal

class ReminderItems(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    
    anxiety_score: bool
    daily_card: bool
    volatility_alert: bool

class ReminderSettingRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    
    enabled: bool
    time_slot: Literal["MORNING", "NOON", "AFTER_MARKET", "EVENING"]
    items: ReminderItems
