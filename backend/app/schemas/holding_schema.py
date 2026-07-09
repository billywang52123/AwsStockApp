from datetime import datetime
from typing import List, Literal, Optional

from pydantic import BaseModel, ConfigDict, Field

# 交易/匯入輸入的共用防呆:拒絕 NaN/Infinity(注意:Infinity 能通過 gt=0,必須用 config 擋)
_NO_NAN_INPUT = ConfigDict(allow_inf_nan=False)

MAX_SHARES = 1_000_000_000
MAX_PRICE = 10_000_000


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
    model_config = _NO_NAN_INPUT

    shares: int = Field(gt=0, le=MAX_SHARES)
    price: Optional[float] = Field(default=None, gt=0, le=MAX_PRICE)
    broker: Optional[str] = None


class OverrideRequest(BaseModel):
    model_config = _NO_NAN_INPUT

    shares: int = Field(ge=0, le=MAX_SHARES)
    broker: Optional[str] = None


class TradeResult(BaseModel):
    holding: Optional[HoldingRead] = None
    realized_pnl: Optional[float] = None
    realized_pnl_percent: Optional[float] = None
    exited: bool = False


class MergeDecision(BaseModel):
    model_config = _NO_NAN_INPUT

    symbol: str
    shares: int = Field(gt=0, le=MAX_SHARES)
    cost: Optional[float] = Field(default=None, gt=0, le=MAX_PRICE)
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
