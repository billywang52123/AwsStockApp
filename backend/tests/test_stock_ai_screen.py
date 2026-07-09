"""AI 找股測試:GPT 名單逐檔驗證、幻覺代號過濾、離線主題 fallback。"""
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
from app.services.openai_service import OpenAIService
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
    db.add(Stock(symbol="2412", name="中華電", market="TW", industry="通信網路"))
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
def fake_yahoo(monkeypatch):
    """假 Yahoo:只有 0056 / 00878 查得到價格,其餘代號視為不存在。"""
    known = {
        "0056": {"close_price": 38.2, "change_percent": 0.5, "volume": 1000},
        "00878": {"close_price": 21.7, "change_percent": -0.3, "volume": 2000},
    }
    monkeypatch.setattr(YahooFinanceService, "fetch_live_price",
                        staticmethod(lambda symbol: known.get(symbol)))
    monkeypatch.setattr(YahooFinanceService, "fetch_display_name",
                        staticmethod(lambda symbol: {
                            "0056": "Yuanta High Dividend ETF",
                            "00878": "Cathay Sustainable High Dividend ETF",
                        }.get(symbol)))
    monkeypatch.setattr(stock_directory_service, "_cache",
                        {"loaded_at": 0.0, "by_symbol": {}})
    monkeypatch.setattr(stock_directory_service, "_load_directory", lambda: {})


def _mock_gpt(monkeypatch, items):
    async def fake_screen(query):
        return items
    monkeypatch.setattr(OpenAIService, "fetch_stock_screen", fake_screen)


def _mock_gpt_offline(monkeypatch):
    async def fake_screen(query):
        return None
    monkeypatch.setattr(OpenAIService, "fetch_stock_screen", fake_screen)


def test_gpt_items_validated_and_hallucination_dropped(client, fake_yahoo, monkeypatch):
    _mock_gpt(monkeypatch, [
        {"symbol": "0056", "name": "元大高股息", "reason": "追蹤高股息指數,配息紀錄長"},
        {"symbol": "9999", "name": "幻覺股", "reason": "不存在的代號"},
        {"symbol": "2412", "name": "中華電", "reason": "電信龍頭,股利長年穩定"},
    ])
    data = client.get("/api/stocks/ai-screen?query=高股息").json()["data"]
    symbols = [item["symbol"] for item in data["items"]]
    assert symbols == ["0056", "2412"]  # 9999 Yahoo 查無 → 被丟掉
    first = data["items"][0]
    assert first["reason"] == "追蹤高股息指數,配息紀錄長"
    assert first["close_price"] == pytest.approx(38.2)  # 入庫時順手寫入的今日價


def test_gpt_item_added_to_watchlist(client, fake_yahoo, monkeypatch):
    """AI 名單裡的新代號要能直接加入觀察清單(驗證時已入庫)。"""
    _mock_gpt(monkeypatch, [
        {"symbol": "00878", "name": "國泰永續高股息", "reason": "季配息"},
    ])
    data = client.get("/api/stocks/ai-screen?query=高股息").json()["data"]
    assert [item["symbol"] for item in data["items"]] == ["00878"]

    list_id = client.post("/api/watchlists", json={"name": "高股息觀察"}).json()["data"]["id"]
    assert client.post(f"/api/watchlists/{list_id}/items",
                       json={"symbol": "00878"}).status_code == 200


def test_offline_fallback_matches_theme(client, fake_yahoo, monkeypatch):
    _mock_gpt_offline(monkeypatch)
    data = client.get("/api/stocks/ai-screen?query=我要高股息").json()["data"]
    symbols = [item["symbol"] for item in data["items"]]
    # 主題名單中只有 0056/00878 通過 Yahoo 驗證,2412 本地已有
    assert symbols == ["0056", "00878", "2412"]
    assert data["note"] is not None


def test_offline_fallback_unknown_theme(client, fake_yahoo, monkeypatch):
    _mock_gpt_offline(monkeypatch)
    data = client.get("/api/stocks/ai-screen?query=會漲的股票").json()["data"]
    assert data["items"] == []
    assert "高股息" in data["note"]


def test_empty_query_returns_hint(client, fake_yahoo):
    data = client.get("/api/stocks/ai-screen?query=").json()["data"]
    assert data["items"] == []
    assert data["note"] is not None
