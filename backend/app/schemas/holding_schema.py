from datetime import datetime
from typing import List, Literal, Optional

from pydantic import BaseModel, Field


class BrokerLotRead(BaseModel):
    id: str
    broker: Optional[str] = None
    shares: int
    avg_price: Optional[float] = None
    source: str = "manual"
    created_at: datetime
    updated_at: datetime


class HoldingRead(BaseModel):
    symbol: str
    name: str
    industry: Optional[str] = None
    total_shares: int
    avg_price: Optional[float] = None
    avg_price_incomplete: bool = False
    lots: List[BrokerLotRead] = []


class TradeRequest(BaseModel):
    shares: int = Field(gt=0)
    price: Optional[float] = Field(default=None, gt=0)
    broker: Optional[str] = None


class OverrideRequest(BaseModel):
    shares: int = Field(ge=0)
    broker: Optional[str] = None


class TradeResult(BaseModel):
    holding: Optional[HoldingRead] = None
    realized_pnl: Optional[float] = None
    realized_pnl_percent: Optional[float] = None
    exited: bool = False


class MergeDecision(BaseModel):
    symbol: str
    shares: int = Field(gt=0)
    cost: Optional[float] = Field(default=None, gt=0)
    broker: Optional[str] = None
    action: Literal["add_lot", "replace_broker", "merge_add", "replace_all", "skip"]


class ImportMergeRequest(BaseModel):
    decisions: List[MergeDecision]


class ImportMergeResult(BaseModel):
    updated_count: int
    holdings: List[HoldingRead] = []


class HoldingActivityRead(BaseModel):
    id: str
    symbol: str
    activity_type: str
    shares_delta: int
    price: Optional[float] = None
    broker: Optional[str] = None
    realized_pnl: Optional[float] = None
    avg_price_after: Optional[float] = None
    created_at: datetime
