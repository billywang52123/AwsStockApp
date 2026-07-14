"""投資風格問卷、習慣快照、prompt context 與個股個人化整合測試。"""

import sys
from datetime import date
from pathlib import Path

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

backend_dir = Path(__file__).resolve().parent.parent
sys.path.append(str(backend_dir))

from app.main import app
from app.db.base import Base
from app.db.database import get_db
from app.models.market_index import MarketIndexDaily
from app.models.stock import Stock
from app.models.stock_daily_price import StockDailyPrice


engine = create_engine(
    "sqlite:///:memory:",
    connect_args={"check_same_thread": False},
    poolclass=StaticPool,
)
TestingSessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)


@pytest.fixture()
def db_session():
    Base.metadata.create_all(bind=engine)
    db = TestingSessionLocal()
    stocks = [
        ("2330", "台積電", "半導體", 1000.0, -1.2),
        ("0050", "元大台灣50", "ETF", 200.0, 0.2),
        ("2412", "中華電", "通信", 120.0, 0.1),
        ("2882", "國泰金", "金融", 60.0, -0.1),
        ("2603", "長榮", "航運", 180.0, 0.4),
    ]
    for symbol, name, industry, close, change in stocks:
        db.add(Stock(symbol=symbol, name=name, market="TW", industry=industry))
        db.add(StockDailyPrice(
            symbol=symbol, trade_date=date(2025, 7, 14),
            close_price=close, change_percent=change, volume=1000,
        ))
    db.add(MarketIndexDaily(
        index_code="TAIEX", trade_date=date.today(),
        close_price=22000, change_percent=-0.5,
    ))
    db.commit()
    try:
        yield db
    finally:
        db.close()
        Base.metadata.drop_all(bind=engine)


@pytest.fixture()
def client(db_session):
    def override_get_db():
        yield db_session

    app.dependency_overrides[get_db] = override_get_db
    yield TestClient(app)
    del app.dependency_overrides[get_db]


CONSERVATIVE = {
    "investment_horizon": "long",
    "risk_tolerance": "conservative",
    "decision_style": "data_driven",
    "trading_frequency": "low",
    "drawdown_response": "review",
    "primary_goal": "preservation",
}

GROWTH = {
    "investment_horizon": "long",
    "risk_tolerance": "aggressive",
    "decision_style": "news_driven",
    "trading_frequency": "medium",
    "drawdown_response": "hold",
    "primary_goal": "growth",
}


def _add(client, symbol, shares=1000, cost=100.0, headers=None):
    response = client.post(
        "/api/portfolio/items",
        headers=headers or {},
        json={"symbol": symbol, "shares": shares, "cost_price": cost},
    )
    assert response.status_code == 201


def test_questionnaire_is_scoped_per_user(client):
    alice = {"X-User-Id": "alice"}
    bob = {"X-User-Id": "bob"}

    response = client.put("/api/investment-profile/questionnaire", headers=alice, json=CONSERVATIVE)
    assert response.status_code == 200
    alice_profile = response.json()["data"]
    assert alice_profile["preference_style"]["code"] == "conservative_guardian"

    bob_questionnaire = client.get("/api/investment-profile/questionnaire", headers=bob).json()["data"]
    assert bob_questionnaire["completed"] is False
    assert bob_questionnaire["current_answers"] is None
    assert len(bob_questionnaire["questions"]) == 6


def test_questionnaire_rejects_unknown_answer(client):
    invalid = {**CONSERVATIVE, "risk_tolerance": "reckless"}
    assert client.put("/api/investment-profile/questionnaire", json=invalid).status_code == 422


def test_holding_updates_create_history_and_observed_style_transition(client):
    client.put("/api/investment-profile/questionnaire", json=GROWTH)
    _add(client, "2330", shares=1000, cost=900)

    concentrated = client.get("/api/investment-profile").json()["data"]
    assert concentrated["observed_style"]["code"] == "focused_growth"
    assert concentrated["portfolio_metrics"]["top_holding_weight"] == pytest.approx(100.0)

    # 五檔近似等值後，觀察風格從集中轉為分散；每次新增都自動留下快照。
    _add(client, "0050", shares=5000, cost=180)
    _add(client, "2412", shares=8333, cost=110)
    _add(client, "2882", shares=16667, cost=55)
    _add(client, "2603", shares=5556, cost=170)

    profile = client.get("/api/investment-profile").json()["data"]
    assert profile["observed_style"]["code"] == "diversified_balancer"
    assert profile["investment_habit"]["code"] == "diversified_holder"

    history = client.get("/api/investment-profile/history").json()["data"]
    assert len(history) >= 6  # 問卷 + 5 次持股新增
    assert history[0]["trigger"] == "holding_added"
    assert any("轉為" in item["change_summary"] for item in history)


def test_prompt_context_combines_preference_habit_and_portfolio_facts(client):
    client.put("/api/investment-profile/questionnaire", json=CONSERVATIVE)
    _add(client, "2330", shares=1000, cost=900)

    data = client.get("/api/investment-profile/prompt-context").json()["data"]
    assert data["prompt_version"] == "investment-context-v1"
    assert data["preference_style"]["label"] == "穩健守護型"
    assert data["investment_habit"]["code"] == "focused_holder"
    assert data["portfolio_facts"]["holding_count"] == 1
    assert "最大持股" in data["prompt_text"]
    assert "不提供任何交易操作方向" in data["prompt_text"]


def test_stock_insight_contains_personalized_style_habit_and_market_analysis(client):
    client.put("/api/investment-profile/questionnaire", json=CONSERVATIVE)
    _add(client, "2330", shares=1000, cost=900)

    response = client.get("/api/insights/2330")
    assert response.status_code == 200
    data = response.json()["data"]
    personalized = data["personalization"]
    assert personalized["preference_style"]["code"] == "conservative_guardian"
    assert personalized["investment_habit"]["code"] == "focused_holder"
    assert {s["key"] for s in personalized["sections"]} == {"style", "habit", "market"}
    assert "-1.20%" in next(s["text"] for s in personalized["sections"] if s["key"] == "market")
    assert personalized["data_date"]


def test_manual_refresh_and_history_are_user_isolated(client):
    alice = {"X-User-Id": "alice"}
    bob = {"X-User-Id": "bob"}
    _add(client, "2330", headers=alice)
    client.post("/api/investment-profile/refresh", headers=alice)

    assert len(client.get("/api/investment-profile/history", headers=alice).json()["data"]) == 2
    assert client.get("/api/investment-profile/history", headers=bob).json()["data"] == []
