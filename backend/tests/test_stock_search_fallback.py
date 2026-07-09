"""股票搜尋 Yahoo fallback 測試:本地沒有的台股代號自動驗證入庫。"""
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
from app.services.yahoo_finance_service import YahooFinanceService
from app.services import stock_directory_service

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
    db.add(Stock(symbol="2330", name="台積電", market="TW", industry="半導體"))
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


@pytest.fixture()
def fake_sources(monkeypatch):
    """假 Yahoo(2603 有價、其他沒有)+ 假證交所目錄(2603=長榮/航運)。"""
    calls = {"live": [], "name": []}

    def fake_live(symbol):
        calls["live"].append(symbol)
        if symbol == "2603":
            return {"close_price": 194.5, "change_percent": 1.2, "volume": 12345}
        return None

    def fake_display_name(symbol):
        calls["name"].append(symbol)
        return "Evergreen Marine ETF" if symbol == "2603" else None

    monkeypatch.setattr(YahooFinanceService, "fetch_live_price", staticmethod(fake_live))
    monkeypatch.setattr(YahooFinanceService, "fetch_display_name", staticmethod(fake_display_name))
    monkeypatch.setattr(stock_directory_service, "_cache",
                        {"loaded_at": 0.0, "by_symbol": {}})
    monkeypatch.setattr(stock_directory_service, "_load_directory",
                        lambda: {"2603": {"name": "長榮", "industry": "航運"}})
    return calls


def test_local_hit_does_not_call_yahoo(client, fake_sources):
    data = client.get("/api/stocks/search?keyword=2330").json()["data"]
    assert [s["symbol"] for s in data] == ["2330"]
    assert fake_sources["live"] == []


def test_unknown_symbol_imported_from_yahoo(client, db_session, fake_sources):
    data = client.get("/api/stocks/search?keyword=2603").json()["data"]
    assert len(data) == 1
    assert data[0]["symbol"] == "2603"
    assert data[0]["name"] == "長榮"          # 證交所中文簡稱優先
    assert data[0]["industry"] == "航運"

    # 已入庫:第二次搜尋直接命中本地,不再打 Yahoo
    fake_sources["live"].clear()
    again = client.get("/api/stocks/search?keyword=2603").json()["data"]
    assert [s["symbol"] for s in again] == ["2603"]
    assert fake_sources["live"] == []

    # 今日價格同步寫入快取
    price = db_session.query(StockDailyPrice).filter_by(
        symbol="2603", trade_date=date.today()).first()
    assert price is not None and price.close_price == pytest.approx(194.5)

    # 入庫後即可加進觀察清單(先前會 404)
    list_id = client.post("/api/watchlists", json={"name": "航運觀察"}).json()["data"]["id"]
    assert client.post(f"/api/watchlists/{list_id}/items",
                       json={"symbol": "2603"}).status_code == 200


def test_directory_miss_falls_back_to_yahoo_name(client, fake_sources, monkeypatch):
    # 目錄查不到 → 用 Yahoo 英文名;名稱含 ETF → 產業標 ETF
    monkeypatch.setattr(stock_directory_service, "_load_directory", lambda: {})
    data = client.get("/api/stocks/search?keyword=2603").json()["data"]
    assert data[0]["name"] == "Evergreen Marine ETF"
    assert data[0]["industry"] == "ETF"


def test_invalid_symbol_returns_empty(client, fake_sources):
    assert client.get("/api/stocks/search?keyword=9999").json()["data"] == []
    assert fake_sources["live"] == ["9999"]


def test_non_symbol_keyword_skips_yahoo(client, fake_sources):
    assert client.get("/api/stocks/search?keyword=聯發科").json()["data"] == []
    assert client.get("/api/stocks/search?keyword=26").json()["data"] == []
    assert fake_sources["live"] == []
