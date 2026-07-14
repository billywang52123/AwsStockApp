"""投資風格/習慣 API schema。"""

from datetime import datetime
from typing import Dict, List, Literal, Optional

from pydantic import BaseModel, Field


InvestmentHorizon = Literal["short", "medium", "long"]
RiskTolerance = Literal["conservative", "balanced", "aggressive"]
DecisionStyle = Literal["data_driven", "news_driven", "intuitive"]
TradingFrequency = Literal["low", "medium", "high"]
DrawdownResponse = Literal["hold", "review", "reduce"]
PrimaryGoal = Literal["preservation", "income", "growth", "learning"]


class QuestionnaireAnswers(BaseModel):
    investment_horizon: InvestmentHorizon
    risk_tolerance: RiskTolerance
    decision_style: DecisionStyle
    trading_frequency: TradingFrequency
    drawdown_response: DrawdownResponse
    primary_goal: PrimaryGoal


class QuestionnaireOption(BaseModel):
    code: str
    label: str
    description: str


class QuestionnaireQuestion(BaseModel):
    id: str
    title: str
    subtitle: str
    options: List[QuestionnaireOption]


class QuestionnaireRead(BaseModel):
    version: int
    completed: bool
    current_answers: Optional[QuestionnaireAnswers] = None
    questions: List[QuestionnaireQuestion]


class StyleRead(BaseModel):
    code: str
    label: str
    summary: str


class HabitRead(BaseModel):
    code: str
    label: str
    summary: str


class StyleDimensions(BaseModel):
    risk: int = Field(ge=0, le=100)
    activity: int = Field(ge=0, le=100)
    horizon: int = Field(ge=0, le=100)
    evidence: int = Field(ge=0, le=100)


class PortfolioHabitMetrics(BaseModel):
    holding_count: int
    industry_count: int
    top_holding_weight: float
    top3_weight: float
    tech_weight: float
    activity_count_30d: int
    buy_count_30d: int
    sell_count_30d: int
    cost_completion_ratio: float


class InvestmentProfileRead(BaseModel):
    questionnaire_completed: bool
    questionnaire_version: int
    preference_style: StyleRead
    observed_style: StyleRead
    investment_habit: HabitRead
    style_dimensions: StyleDimensions
    portfolio_metrics: PortfolioHabitMetrics
    latest_change: str
    updated_at: Optional[datetime] = None
    prompt_version: str


class HabitSnapshotRead(BaseModel):
    id: str
    trigger: str
    preference_style_code: str
    observed_style: StyleRead
    investment_habit: HabitRead
    portfolio_metrics: PortfolioHabitMetrics
    change_summary: str
    created_at: datetime


class PromptContextRead(BaseModel):
    prompt_version: str
    preference_style: StyleRead
    observed_style: StyleRead
    investment_habit: HabitRead
    applied_principles: List[str]
    portfolio_facts: Dict[str, float | int]
    prompt_text: str

