"""股票搜尋 CMoney fallback 測試:本地沒有的台股代號自動驗證入庫。

模擬情境下唯一資料源是 CMoney:代號必須在模擬日有收盤價才視為存在,
名稱優先 CMoney 目錄(raw_07),再退證交所目錄,最後用代號。
"""
import sys
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
from app.services import services as services_module
from app.services import stock_directory_service
from app.services.cmoney_service import effective_trade_date

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
    """假 CMoney(2603 有模擬日收盤、其他沒有)+ 假證交所目錄(2603=長榮/航運)。"""
    calls = {"live": []}

    def fake_live(db, symbol):
        calls["live"].append(symbol)
        if symbol == "2603":
            return {"close_price": 194.5, "change_percent": 1.2, "volume": 12345}
        return None

    monkeypatch.setattr(services_module, "fetch_sim_price", fake_live)
    monkeypatch.setattr(services_module, "fetch_sim_profile", lambda db, symbol: None)
    monkeypatch.setattr(stock_directory_service, "_cache",
                        {"loaded_at": 0.0, "by_symbol": {}})
    monkeypatch.setattr(stock_directory_service, "_load_directory",
                        lambda: {"2603": {"name": "長榮", "industry": "航運"}})
    return calls


def test_local_hit_does_not_call_cmoney(client, fake_sources):
    data = client.get("/api/stocks/search?keyword=2330").json()["data"]
    assert [s["symbol"] for s in data] == ["2330"]
    assert fake_sources["live"] == []


def test_unknown_symbol_imported_from_cmoney(client, db_session, fake_sources):
    data = client.get("/api/stocks/search?keyword=2603").json()["data"]
    assert len(data) == 1
    assert data[0]["symbol"] == "2603"
    assert data[0]["name"] == "長榮"          # CMoney 目錄查無 → 證交所中文簡稱
    assert data[0]["industry"] == "航運"

    # 已入庫:第二次搜尋直接命中本地,不再查 CMoney
    fake_sources["live"].clear()
    again = client.get("/api/stocks/search?keyword=2603").json()["data"]
    assert [s["symbol"] for s in again] == ["2603"]
    assert fake_sources["live"] == []

    # 今日(14:30 換日)價格同步寫入快取
    price = db_session.query(StockDailyPrice).filter_by(
        symbol="2603", trade_date=effective_trade_date()).first()
    assert price is not None and price.close_price == pytest.approx(194.5)

    # 入庫後即可加進觀察清單(先前會 404)
    list_id = client.post("/api/watchlists", json={"name": "航運觀察"}).json()["data"]["id"]
    assert client.post(f"/api/watchlists/{list_id}/items",
                       json={"symbol": "2603"}).status_code == 200


def test_cmoney_directory_name_preferred(client, fake_sources, monkeypatch):
    # CMoney 目錄有名稱/產業 → 優先於證交所目錄
    monkeypatch.setattr(
        services_module, "fetch_sim_profile",
        lambda db, symbol: {"name": "長榮海運", "industry": "航運業"} if symbol == "2603" else None,
    )
    data = client.get("/api/stocks/search?keyword=2603").json()["data"]
    assert data[0]["name"] == "長榮海運"
    assert data[0]["industry"] == "航運業"


def test_directory_miss_etf_heuristic(client, fake_sources, monkeypatch):
    # 兩邊目錄都查不到 → 用 CMoney 名稱;名稱含 ETF → 產業標 ETF
    monkeypatch.setattr(stock_directory_service, "_load_directory", lambda: {})
    monkeypatch.setattr(
        services_module, "fetch_sim_profile",
        lambda db, symbol: {"name": "Evergreen Marine ETF", "industry": None},
    )
    data = client.get("/api/stocks/search?keyword=2603").json()["data"]
    assert data[0]["name"] == "Evergreen Marine ETF"
    assert data[0]["industry"] == "ETF"


def test_invalid_symbol_returns_empty(client, fake_sources):
    assert client.get("/api/stocks/search?keyword=9999").json()["data"] == []
    assert fake_sources["live"] == ["9999"]


def test_non_symbol_keyword_skips_cmoney(client, fake_sources):
    assert client.get("/api/stocks/search?keyword=聯發科").json()["data"] == []
    assert client.get("/api/stocks/search?keyword=26").json()["data"] == []
    assert fake_sources["live"] == []
