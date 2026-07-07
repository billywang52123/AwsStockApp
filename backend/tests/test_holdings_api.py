"""spec 04「合併與均價計算規則」表的驗證(9a–9e 後端)."""

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
    db.add(Stock(symbol="2330", name="台積電", market="TW", industry="半導體"))
    db.add(Stock(symbol="0050", name="元大台灣50", market="TW", industry="ETF"))
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


def _seed(client, symbol="2330", shares=3000, cost=900.0):
    resp = client.post("/api/portfolio/items", json={
        "symbol": symbol, "shares": shares, "cost_price": cost,
    })
    assert resp.status_code == 201


def _holding(client, symbol="2330"):
    resp = client.get(f"/api/portfolio/holdings/{symbol}")
    assert resp.status_code == 200
    return resp.json()["data"]


# ---- 9b 加碼 -----------------------------------------------------------------

def test_buy_weighted_average(client):
    """加碼:新均價 = (3000×900 + 500×1030) ÷ 3500 = 918.6(捨入至 0.1)."""
    _seed(client)
    resp = client.post("/api/portfolio/holdings/2330/buy",
                       json={"shares": 500, "price": 1030})
    assert resp.status_code == 200
    holding = resp.json()["data"]["holding"]
    assert holding["total_shares"] == 3500
    assert holding["avg_price"] == pytest.approx(918.6)
    assert holding["avg_price_incomplete"] is False


def test_buy_without_price_keeps_avg(client):
    """加碼未填買價:只加股數、均價不變,不掛 incomplete(該分帳已有均價)."""
    _seed(client)
    resp = client.post("/api/portfolio/holdings/2330/buy", json={"shares": 500})
    assert resp.status_code == 200
    holding = resp.json()["data"]["holding"]
    assert holding["total_shares"] == 3500
    assert holding["avg_price"] == pytest.approx(900.0)


# ---- 9c 賣出 -----------------------------------------------------------------

def test_sell_realized_pnl_and_avg_unchanged(client):
    """賣出:股數減、均價不變;已實現損益 = (1000−900)×500 = 50000."""
    _seed(client)
    resp = client.post("/api/portfolio/holdings/2330/sell",
                       json={"shares": 500, "price": 1000})
    assert resp.status_code == 200
    data = resp.json()["data"]
    assert data["realized_pnl"] == pytest.approx(50000)
    assert data["realized_pnl_percent"] == pytest.approx(11.1)
    assert data["holding"]["total_shares"] == 2500
    assert data["holding"]["avg_price"] == pytest.approx(900.0)
    assert data["exited"] is False


def test_sell_over_position_rejected(client):
    _seed(client)
    resp = client.post("/api/portfolio/holdings/2330/sell",
                       json={"shares": 9999, "price": 1000})
    assert resp.status_code == 400


def test_sell_all_exits_and_restore(client):
    """全部賣出 → 移到已出場(soft delete);restore 還原股數."""
    _seed(client)
    resp = client.post("/api/portfolio/holdings/2330/sell",
                       json={"shares": 3000, "price": 1000})
    assert resp.json()["data"]["exited"] is True
    # 已出場後查不到
    assert client.get("/api/portfolio/holdings/2330").status_code == 404

    resp = client.post("/api/portfolio/holdings/2330/restore")
    assert resp.status_code == 200
    holding = resp.json()["data"]["holding"]
    assert holding["total_shares"] == 3000
    assert holding["avg_price"] == pytest.approx(900.0)


# ---- 覆蓋 ---------------------------------------------------------------------

def test_override_replaces_shares_keeps_avg(client):
    _seed(client)
    resp = client.post("/api/portfolio/holdings/2330/override", json={"shares": 2000})
    assert resp.status_code == 200
    holding = resp.json()["data"]["holding"]
    assert holding["total_shares"] == 2000
    assert holding["avg_price"] == pytest.approx(900.0)


# ---- 9d 匯入合併 ---------------------------------------------------------------

def test_import_add_lot_weighted_across_brokers(client):
    """不同券商 → 新分帳;總覽均價 = 各分帳加權 (2000×900 + 1000×960)/3000 = 920."""
    _seed(client, shares=2000, cost=900.0)
    resp = client.post("/api/portfolio/import/merge", json={"decisions": [
        {"symbol": "2330", "shares": 1000, "cost": 960,
         "broker": "富邦證券", "action": "add_lot"},
    ]})
    assert resp.status_code == 200
    holding = _holding(client)
    assert holding["total_shares"] == 3000
    assert holding["avg_price"] == pytest.approx(920.0)
    assert len(holding["lots"]) == 2


def test_import_replace_broker_is_snapshot(client):
    """同券商 → 視為最新快照,取代該分帳."""
    client.post("/api/portfolio/import/merge", json={"decisions": [
        {"symbol": "2330", "shares": 2000, "cost": 900,
         "broker": "富邦證券", "action": "add_lot"},
    ]})
    client.post("/api/portfolio/import/merge", json={"decisions": [
        {"symbol": "2330", "shares": 2500, "cost": 910,
         "broker": "富邦證券", "action": "replace_broker"},
    ]})
    holding = _holding(client)
    assert holding["total_shares"] == 2500
    assert holding["avg_price"] == pytest.approx(910.0)
    assert len(holding["lots"]) == 1


def test_import_replace_all_deletes_other_lots(client):
    _seed(client, shares=2000, cost=900.0)
    client.post("/api/portfolio/import/merge", json={"decisions": [
        {"symbol": "2330", "shares": 1000, "cost": 960,
         "broker": "富邦證券", "action": "add_lot"},
    ]})
    client.post("/api/portfolio/import/merge", json={"decisions": [
        {"symbol": "2330", "shares": 500, "cost": 1000,
         "broker": "國泰證券", "action": "replace_all"},
    ]})
    holding = _holding(client)
    assert holding["total_shares"] == 500
    assert len(holding["lots"]) == 1
    assert holding["lots"][0]["broker"] == "國泰證券"


def test_import_without_cost_flags_incomplete(client):
    """匯入無均價:分帳不計入加權,聚合掛 avg_price_incomplete."""
    _seed(client, shares=2000, cost=900.0)
    client.post("/api/portfolio/import/merge", json={"decisions": [
        {"symbol": "2330", "shares": 1000, "cost": None,
         "broker": "富邦證券", "action": "add_lot"},
    ]})
    holding = _holding(client)
    assert holding["total_shares"] == 3000
    # 均價只用有成本的分帳加權
    assert holding["avg_price"] == pytest.approx(900.0)
    assert holding["avg_price_incomplete"] is True


def test_import_skip_changes_nothing(client):
    _seed(client)
    resp = client.post("/api/portfolio/import/merge", json={"decisions": [
        {"symbol": "2330", "shares": 1000, "cost": 950,
         "broker": "富邦證券", "action": "skip"},
    ]})
    assert resp.json()["data"]["updated_count"] == 0
    assert _holding(client)["total_shares"] == 3000


# ---- 9e 異動紀錄 ---------------------------------------------------------------

def test_activity_log_and_delete_recalculates(client):
    """買進記 log;刪除該筆異動要回算股數與均價."""
    _seed(client)
    client.post("/api/portfolio/holdings/2330/buy",
                json={"shares": 500, "price": 1030})

    acts = client.get("/api/portfolio/holdings/2330/activities").json()["data"]
    buy_act = next(a for a in acts if a["activity_type"] == "buy")
    assert buy_act["shares_delta"] == 500

    resp = client.delete(f"/api/portfolio/activities/{buy_act['id']}")
    assert resp.status_code == 200
    holding = _holding(client)
    assert holding["total_shares"] == 3000
    assert holding["avg_price"] == pytest.approx(900.0)
