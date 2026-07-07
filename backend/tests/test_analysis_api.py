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
from app.models.stock import Stock
from app.models.stock_daily_price import StockDailyPrice
from app.models.market_index import MarketIndexDaily
from app.models.portfolio import PortfolioItem

SQLALCHEMY_DATABASE_URL = "sqlite:///:memory:"
engine = create_engine(
    SQLALCHEMY_DATABASE_URL,
    connect_args={"check_same_thread": False},
    poolclass=StaticPool
)
TestingSessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)


@pytest.fixture()
def db_session():
    Base.metadata.create_all(bind=engine)
    db = TestingSessionLocal()

    today = date.today()
    db.add_all([
        Stock(symbol="2330", name="台積電", market="TW", industry="半導體"),
        Stock(symbol="2454", name="聯發科", market="TW", industry="IC設計"),
        Stock(symbol="0050", name="元大台灣50", market="TW", industry="ETF"),
        StockDailyPrice(symbol="2330", trade_date=today, close_price=980.0, change_percent=-1.2, volume=1000),
        StockDailyPrice(symbol="2454", trade_date=today, close_price=1250.0, change_percent=0.8, volume=500),
        StockDailyPrice(symbol="0050", trade_date=today, close_price=185.0, change_percent=-0.4, volume=800),
        MarketIndexDaily(index_code="TAIEX", trade_date=today, close_price=22000.0, change_percent=-0.9),
    ])
    db.commit()

    try:
        yield db
    finally:
        db.close()
        Base.metadata.drop_all(bind=engine)


@pytest.fixture()
def client(db_session):
    def override_get_db():
        try:
            yield db_session
        finally:
            pass

    app.dependency_overrides[get_db] = override_get_db
    yield TestClient(app)
    del app.dependency_overrides[get_db]


def seed_portfolio(db):
    db.add_all([
        PortfolioItem(user_id="demo-user", symbol="2330", cost_price=900.0, shares=3000),
        PortfolioItem(user_id="demo-user", symbol="2454", cost_price=1300.0, shares=500),
        PortfolioItem(user_id="demo-user", symbol="0050", cost_price=170.0, shares=5000),
    ])
    db.commit()


# ── /portfolio/analysis ──────────────────────────────────────

def test_analysis_empty_portfolio(client):
    response = client.get("/api/portfolio/analysis")
    assert response.status_code == 200
    data = response.json()["data"]
    assert data["holdings_count"] == 0
    assert data["total_market_value"] == 0
    assert data["holdings"] == []
    assert data["risk_notices"] == []


def test_analysis_with_holdings(client, db_session):
    seed_portfolio(db_session)
    response = client.get("/api/portfolio/analysis")
    assert response.status_code == 200
    data = response.json()["data"]

    # 2330: 980*3000=2,940,000 · 2454: 1250*500=625,000 · 0050: 185*5000=925,000
    assert data["holdings_count"] == 3
    assert data["total_market_value"] == pytest.approx(4490000, abs=1)
    # 成本 900*3000 + 1300*500 + 170*5000 = 4,200,000 → 損益 +290,000
    assert data["unrealized_pnl"] == pytest.approx(290000, abs=1)
    assert data["unrealized_pnl_percent"] == pytest.approx(6.9, abs=0.1)

    # 權重排序:台積電最大
    assert data["holdings"][0]["symbol"] == "2330"
    assert data["holdings"][0]["weight_percent"] == pytest.approx(65.5, abs=0.2)
    total_weight = sum(h["weight_percent"] for h in data["holdings"])
    assert total_weight == pytest.approx(100.0, abs=0.5)

    # 曝險依權重排序且加總約 100
    industries = [seg["industry"] for seg in data["exposure"]]
    assert industries[0] == "半導體"
    assert sum(seg["percent"] for seg in data["exposure"]) == pytest.approx(100.0, abs=0.5)

    # 科技類 = 半導體 + IC設計
    assert data["tech_exposure_percent"] > 60

    assert 0 < data["risk_score"] <= 100
    assert 0 <= data["anxiety_score"] <= 100

    # 台積電權重 > 40% → rose;科技曝險 > 60% → amber
    severities = [n["severity"] for n in data["risk_notices"]]
    assert "rose" in severities
    assert "amber" in severities
    for notice in data["risk_notices"]:
        assert notice["badge"] in ("優先檢查", "注意")
        assert notice["plain_talk"].startswith("白話說")
        assert notice["highlight"] in notice["body"]


def test_analysis_user_isolation(client, db_session):
    seed_portfolio(db_session)
    response = client.get("/api/portfolio/analysis", headers={"X-User-Id": "someone-else"})
    assert response.status_code == 200
    assert response.json()["data"]["holdings_count"] == 0


# ── /insights ────────────────────────────────────────────────

def test_insights_list(client, db_session):
    seed_portfolio(db_session)
    response = client.get("/api/insights")
    assert response.status_code == 200
    data = response.json()["data"]

    assert len(data["items"]) == 3
    assert data["bullish_count"] + data["neutral_count"] + data["caution_count"] == 3

    # 依權重排序
    assert data["items"][0]["symbol"] == "2330"
    for item in data["items"]:
        assert item["outlook"] in ("bullish", "neutral", "caution")
        assert 0 <= item["outlook_score"] <= 100
        assert len(item["headline"]) > 0


def test_insight_detail(client, db_session):
    seed_portfolio(db_session)
    response = client.get("/api/insights/2330")
    assert response.status_code == 200
    data = response.json()["data"]

    assert data["symbol"] == "2330"
    assert data["name"] == "台積電"
    assert 0 <= data["outlook_score"] <= 100
    assert "·" in data["stance_label"]
    assert len(data["signals"]) == 3
    for signal in data["signals"]:
        assert signal["direction"] in ("bullish", "bearish", "neutral")
        assert signal["direction_label"].startswith("→")
        assert len(signal["text"]) > 0
    assert len(data["plain_summary"]) > 0

    # 台積電今日 -1.2% 但成本 900 有獲利 → 短線留意、長線看好
    assert data["stance_label"] == "短線留意 · 長線看好"


def test_insight_detail_not_found(client, db_session):
    seed_portfolio(db_session)
    response = client.get("/api/insights/9999")
    assert response.status_code == 404
