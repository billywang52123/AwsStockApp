"""NaN 防護回歸測試。

背景:台股開盤初期 Yahoo 的當日列常帶 NaN,NaN 一路流進回應後
會被 pydantic 序列化成 null,導致 iOS 端非 optional 欄位解碼失敗
(2026-07-09 正式區 /portfolio/analysis total_market_value: null 事件)。
"""
import math
import sys
from datetime import date
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

import pandas as pd
import pytest
from fastapi.testclient import TestClient
from pydantic import ValidationError
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
from app.schemas.analysis_schema import PortfolioAnalysisRead
from app.schemas.market_schema import MarketCompareResultRead
from app.services.yahoo_finance_service import YahooFinanceService
from app.services.services import is_finite_number, finite_or_zero
from app.services.portfolio_analysis_service import _Holding


# ── 工具函式 ─────────────────────────────────────────────────

def test_is_finite_number():
    assert is_finite_number(1.5)
    assert is_finite_number(0)
    assert not is_finite_number(float("nan"))
    assert not is_finite_number(float("inf"))
    assert not is_finite_number(None)
    assert not is_finite_number("abc")


def test_finite_or_zero():
    assert finite_or_zero(-2.3) == -2.3
    assert finite_or_zero(float("nan")) == 0.0
    assert finite_or_zero(None) == 0.0


# ── Yahoo 抓價:NaN 視同沒抓到 ───────────────────────────────

def _mock_history(rows):
    return pd.DataFrame(rows)


def test_fetch_live_price_nan_close_returns_none():
    hist = _mock_history([
        {"Open": 100.0, "Close": 100.0, "Volume": 1000},
        {"Open": float("nan"), "Close": float("nan"), "Volume": 0},
    ])
    with patch("app.services.yahoo_finance_service.yf.Ticker") as ticker_cls:
        ticker_cls.return_value.history.return_value = hist
        assert YahooFinanceService.fetch_live_price("2330") is None


def test_fetch_live_price_nan_prev_close_falls_back_to_zero_change():
    hist = _mock_history([
        {"Open": 100.0, "Close": float("nan"), "Volume": 1000},
        {"Open": 101.0, "Close": 102.0, "Volume": float("nan")},
    ])
    with patch("app.services.yahoo_finance_service.yf.Ticker") as ticker_cls:
        ticker_cls.return_value.history.return_value = hist
        data = YahooFinanceService.fetch_live_price("2330")
    assert data is not None
    assert data["close_price"] == 102.0
    assert data["change_percent"] == 0.0
    assert data["volume"] == 0


# ── 分析服務:NaN 價格/成本視為缺值,不污染加總 ──────────────

def test_holding_sanitizes_nan_inputs():
    item = SimpleNamespace(id="x", symbol="2330", shares=10, cost_price=float("nan"))
    price = SimpleNamespace(close_price=float("nan"), change_percent=float("nan"))
    h = _Holding(item, stock=None, price=price)
    assert h.cost is None
    assert h.close is None
    assert h.change == 0.0
    assert h.market_value == 0.0
    assert math.isfinite(h.pnl)
    assert math.isfinite(h.pnl_percent)


# ── Schema 保險:NaN 直接驗證失敗(500),不再默默變 null ─────

def test_schemas_reject_nan():
    with pytest.raises(ValidationError):
        MarketCompareResultRead(
            portfolio_change_percent=float("nan"),
            market_change_percent=0.5,
            message="x",
        )
    base = dict(
        total_market_value=0, total_cost=0, unrealized_pnl=0,
        unrealized_pnl_percent=0, holdings_count=0, risk_score=0,
        risk_note="x", anxiety_score=0, anxiety_note="x", exposure=[],
        tech_exposure_percent=0, exposure_note="x", holdings=[], risk_notices=[],
    )
    assert PortfolioAnalysisRead(**base).total_market_value == 0
    with pytest.raises(ValidationError):
        PortfolioAnalysisRead(**{**base, "total_market_value": float("nan")})


# ── API 端對端:壞掉的當日價不會讓分析/對比回 null ───────────

SQLALCHEMY_DATABASE_URL = "sqlite:///:memory:"
engine = create_engine(
    SQLALCHEMY_DATABASE_URL,
    connect_args={"check_same_thread": False},
    poolclass=StaticPool,
)
TestingSessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)


@pytest.fixture()
def db_session():
    Base.metadata.create_all(bind=engine)
    db = TestingSessionLocal()
    today = date.today()
    db.add_all([
        Stock(symbol="2330", name="台積電", market="TW", industry="半導體"),
        StockDailyPrice(symbol="2330", trade_date=today, close_price=980.0, change_percent=-1.2, volume=1000),
        # 0056 模擬「早盤壞資料被淨化後」的狀態:今天沒有可用價格列
        # (SQLite 存不了 NaN;NaN 情境已在上面的單元測試覆蓋)
        Stock(symbol="0056", name="高股息", market="TW", industry="ETF"),
        MarketIndexDaily(index_code="TAIEX", trade_date=today, close_price=22000.0, change_percent=-0.9),
        PortfolioItem(user_id="demo-user", symbol="2330", cost_price=900.0, shares=1000),
        PortfolioItem(user_id="demo-user", symbol="0056", cost_price=30.0, shares=1000),
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
        yield db_session

    app.dependency_overrides[get_db] = override_get_db
    yield TestClient(app)
    del app.dependency_overrides[get_db]


def test_analysis_survives_bad_daily_price(client):
    # 0056 的當日價已被污染,重抓也失敗 → 應以缺值處理而非回 null/500
    with patch(
        "app.services.yahoo_finance_service.YahooFinanceService.fetch_live_price",
        return_value=None,
    ):
        response = client.get("/api/portfolio/analysis")
    assert response.status_code == 200
    data = response.json()["data"]
    assert data["total_market_value"] is not None
    assert math.isfinite(data["total_market_value"])
    # 0056 沒有可用收盤價 → 退回用成本估值 30*1000
    assert data["total_market_value"] == pytest.approx(980.0 * 1000 + 30.0 * 1000, abs=1)


def test_portfolio_item_create_rejects_nan(client):
    # Python 的 json.loads 接受 NaN/Infinity literal,必須靠 schema 的 allow_inf_nan=False 擋
    response = client.post(
        "/api/portfolio/items",
        content='{"symbol": "2330", "cost_price": NaN, "shares": 10}',
        headers={"Content-Type": "application/json"},
    )
    assert response.status_code == 422


def test_trade_rejects_infinite_price(client):
    # Infinity 能通過 gt=0 的檢查,必須靠 allow_inf_nan=False 擋
    response = client.post(
        "/api/portfolio/holdings/2330/buy",
        content='{"shares": 10, "price": Infinity}',
        headers={"Content-Type": "application/json"},
    )
    assert response.status_code == 422


def test_trade_rejects_absurd_shares(client):
    response = client.post(
        "/api/portfolio/holdings/2330/buy",
        json={"shares": 10_000_000_000, "price": 100.0},
    )
    assert response.status_code == 422


def test_market_compare_survives_bad_daily_price(client):
    with patch(
        "app.services.yahoo_finance_service.YahooFinanceService.fetch_live_price",
        return_value=None,
    ):
        response = client.get("/api/market/compare")
    assert response.status_code == 200
    data = response.json()["data"]
    assert data["portfolio_change_percent"] is not None
    assert math.isfinite(data["portfolio_change_percent"])
