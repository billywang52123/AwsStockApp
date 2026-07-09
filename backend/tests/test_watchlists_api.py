"""觀察清單 API 測試(spec 05 · 11a–11g)。"""
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
        Stock(symbol="0056", name="元大高股息", market="TW", industry="ETF"),
        Stock(symbol="3443", name="創意", market="TW", industry="半導體"),
        StockDailyPrice(symbol="2330", trade_date=today, close_price=980.0, change_percent=-1.2, volume=1000),
        StockDailyPrice(symbol="2454", trade_date=today, close_price=1250.0, change_percent=2.0, volume=500),
        StockDailyPrice(symbol="0056", trade_date=today, close_price=38.0, change_percent=0.1, volume=800),
        StockDailyPrice(symbol="3443", trade_date=today, close_price=1400.0, change_percent=-2.2, volume=300),
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


def create_list(client, name="半導體觀察", color="#7B7FD4") -> str:
    response = client.post("/api/watchlists", json={"name": name, "color": color})
    assert response.status_code == 200
    return response.json()["data"]["id"]


# ── 11a / 11b · 清單 CRUD ────────────────────────────────────

def test_create_and_index(client, db_session):
    db_session.add(PortfolioItem(user_id="demo-user", symbol="2330", cost_price=900.0, shares=1000))
    db_session.commit()

    list_id = create_list(client)
    client.post(f"/api/watchlists/{list_id}/items", json={"symbol": "2454"})

    data = client.get("/api/watchlists").json()["data"]
    assert data["holding_count"] == 1
    assert len(data["watchlists"]) == 1
    assert data["watchlists"][0]["name"] == "半導體觀察"
    assert data["watchlists"][0]["color"] == "#7B7FD4"
    assert data["watchlists"][0]["stock_count"] == 1


def test_create_blank_name_rejected(client):
    response = client.post("/api/watchlists", json={"name": "   ", "color": None})
    assert response.status_code == 400


def test_delete_watchlist(client):
    list_id = create_list(client)
    client.post(f"/api/watchlists/{list_id}/items", json={"symbol": "2454"})
    assert client.delete(f"/api/watchlists/{list_id}").status_code == 200
    assert client.get(f"/api/watchlists/{list_id}").status_code == 404
    assert client.get("/api/watchlists").json()["data"]["watchlists"] == []


def test_user_isolation(client):
    create_list(client)
    data = client.get("/api/watchlists", headers={"X-User-Id": "someone-else"}).json()["data"]
    assert data["watchlists"] == []


# ── 11c · 清單頁 ─────────────────────────────────────────────

def test_detail_scores_and_counts(client):
    list_id = create_list(client)
    for symbol in ("2330", "2454", "0056"):
        client.post(f"/api/watchlists/{list_id}/items", json={"symbol": symbol})

    data = client.get(f"/api/watchlists/{list_id}").json()["data"]
    assert data["stock_count"] == 3
    # 2454 +2.0% → 62 bullish;0056 +0.1% → 51 neutral;2330 -1.2% → 43 neutral
    assert data["bullish_count"] == 1
    assert data["neutral_count"] == 2
    assert data["caution_count"] == 0
    assert data["average_score"] == 52
    # 依評分排序
    assert [i["symbol"] for i in data["items"]] == ["2454", "0056", "2330"]
    top = data["items"][0]
    assert top["ai_score"] == 62 and top["outlook"] == "bullish"
    assert top["close_price"] == pytest.approx(1250.0)
    # 觀察清單不出現買賣字眼
    for item in data["items"]:
        for banned in ("買進", "賣出", "建議", "加碼"):
            assert banned not in item["headline"]


def test_add_duplicate_symbol_idempotent(client):
    list_id = create_list(client)
    client.post(f"/api/watchlists/{list_id}/items", json={"symbol": "2330"})
    client.post(f"/api/watchlists/{list_id}/items", json={"symbol": "2330"})
    data = client.get(f"/api/watchlists/{list_id}").json()["data"]
    assert data["stock_count"] == 1


def test_add_unknown_symbol_404(client):
    list_id = create_list(client)
    assert client.post(f"/api/watchlists/{list_id}/items", json={"symbol": "9999"}).status_code == 404


def test_remove_item(client):
    list_id = create_list(client)
    client.post(f"/api/watchlists/{list_id}/items", json={"symbol": "2330"})
    assert client.delete(f"/api/watchlists/{list_id}/items/2330").status_code == 200
    assert client.get(f"/api/watchlists/{list_id}").json()["data"]["stock_count"] == 0


# ── 11d · 轉入庫存 ───────────────────────────────────────────

def test_convert_to_holding(client):
    list_id = create_list(client)
    client.post(f"/api/watchlists/{list_id}/items", json={"symbol": "2330"})

    response = client.post(
        f"/api/watchlists/{list_id}/items/2330/convert",
        json={"shares": 1200, "price": 950.0},
    )
    assert response.status_code == 200
    data = response.json()["data"]
    assert data["watchlist_name"] == "半導體觀察"
    assert data["total_shares"] == 1200
    assert data["avg_price"] == pytest.approx(950.0)

    # 已移出觀察清單、進入持股
    assert client.get(f"/api/watchlists/{list_id}").json()["data"]["stock_count"] == 0
    holding = client.get("/api/portfolio/holdings/2330").json()["data"]
    assert holding["total_shares"] == 1200

    # 轉入後開始計入分析
    analysis = client.get("/api/portfolio/analysis").json()["data"]
    assert analysis["holdings_count"] == 1


def test_convert_without_price(client):
    list_id = create_list(client)
    client.post(f"/api/watchlists/{list_id}/items", json={"symbol": "0056"})
    response = client.post(
        f"/api/watchlists/{list_id}/items/0056/convert", json={"shares": 500},
    )
    assert response.status_code == 200
    assert response.json()["data"]["avg_price"] is None


def test_convert_not_in_list_404(client):
    list_id = create_list(client)
    response = client.post(
        f"/api/watchlists/{list_id}/items/2330/convert", json={"shares": 1000},
    )
    assert response.status_code == 404


# ── 11e · 觀察清單分析 ───────────────────────────────────────

def test_analysis_empty(client):
    data = client.get("/api/watchlists/analysis").json()["data"]
    assert data["watch_count"] == 0
    assert data["exposure"] == []
    assert data["overlap_notice"] is None


def test_analysis_exposure_and_overlap(client, db_session):
    # 庫存:半導體 2330;觀察:半導體 3443 + ETF 0056 → 半導體重疊
    db_session.add(PortfolioItem(user_id="demo-user", symbol="2330", cost_price=900.0, shares=1000))
    db_session.commit()

    list_id = create_list(client)
    client.post(f"/api/watchlists/{list_id}/items", json={"symbol": "3443"})
    client.post(f"/api/watchlists/{list_id}/items", json={"symbol": "0056"})

    data = client.get("/api/watchlists/analysis").json()["data"]
    assert data["watch_count"] == 2
    exposure = {seg["industry"]: seg["percent"] for seg in data["exposure"]}
    assert exposure == {"半導體": 50.0, "ETF": 50.0}

    notice = data["overlap_notice"]
    assert notice is not None
    assert notice["title"] == "與你的庫存重疊提醒"
    assert "半導體" in notice["body"]
    assert notice["highlight"] in notice["body"]
    # 庫存 980,000 全在半導體(100%);轉入 3443 一張 1,400,000 + 0056 38,000
    # → 半導體 (980k+1400k)/2418k ≈ 98%
    assert "100% → 98%" in notice["highlight"]


def test_analysis_no_overlap(client, db_session):
    db_session.add(PortfolioItem(user_id="demo-user", symbol="2330", cost_price=900.0, shares=1000))
    db_session.commit()
    list_id = create_list(client)
    client.post(f"/api/watchlists/{list_id}/items", json={"symbol": "0056"})

    data = client.get("/api/watchlists/analysis").json()["data"]
    assert data["overlap_notice"] is None


def test_analysis_filter_by_list(client):
    a = create_list(client, name="半導體觀察")
    b = create_list(client, name="高股息名單")
    client.post(f"/api/watchlists/{a}/items", json={"symbol": "3443"})
    client.post(f"/api/watchlists/{b}/items", json={"symbol": "0056"})

    data = client.get(f"/api/watchlists/analysis?watchlist_id={a}").json()["data"]
    assert data["watch_count"] == 1
    assert data["exposure"][0]["industry"] == "半導體"

    data_all = client.get("/api/watchlists/analysis").json()["data"]
    assert data_all["watch_count"] == 2


# ── 11f · 觀點分頁 ───────────────────────────────────────────

def test_watch_insights(client):
    a = create_list(client, name="半導體觀察")
    b = create_list(client, name="高股息名單")
    client.post(f"/api/watchlists/{a}/items", json={"symbol": "2454"})
    client.post(f"/api/watchlists/{b}/items", json={"symbol": "0056"})

    data = client.get("/api/watchlists/insights").json()["data"]
    assert data["bullish_count"] == 1
    assert data["neutral_count"] == 1
    assert len(data["items"]) == 2
    # 依評分排序,subtitle 是清單名而非權重
    assert data["items"][0]["symbol"] == "2454"
    assert data["items"][0]["watchlist_name"] == "半導體觀察"
    assert data["items"][1]["watchlist_name"] == "高股息名單"


# ── 11g · 推薦星標 ───────────────────────────────────────────

def test_recommendations_watchlist_flag(client):
    list_id = create_list(client, name="半導體觀察")
    client.post(f"/api/watchlists/{list_id}/items", json={"symbol": "2454"})

    response = client.get("/api/recommendations/stocks?symbol=2330")
    assert response.status_code == 200
    items = response.json()["data"]
    by_symbol = {i["symbol"]: i for i in items}
    if "2454" in by_symbol:
        rec = by_symbol["2454"]
        assert rec["in_watchlist"] is True
        assert rec["watchlist_name"] == "半導體觀察"
    for sym, rec in by_symbol.items():
        if sym != "2454":
            assert rec["in_watchlist"] is False
            assert rec["watchlist_name"] is None
