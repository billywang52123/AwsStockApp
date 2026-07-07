"""spec 05 · 10a 隱私儀表板 API:摘要即時、刪除同步且回報筆數."""

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


def _seed_user_data(client):
    client.post("/api/portfolio/items", json={"symbol": "2330", "shares": 1000, "cost_price": 900})
    # buy 產生一筆異動紀錄
    client.post("/api/portfolio/holdings/2330/buy", json={"shares": 100, "price": 950})


def test_summary_reflects_stored_data(client):
    _seed_user_data(client)
    resp = client.get("/api/privacy/summary")
    assert resp.status_code == 200
    data = resp.json()["data"]
    assert data["holdings"] == 1
    assert data["activities"] == 1


def test_delete_all_is_immediate_and_reports_counts(client):
    _seed_user_data(client)
    resp = client.delete("/api/privacy/all")
    assert resp.status_code == 200
    deleted = resp.json()["data"]["deleted"]
    assert deleted["holdings"] == 1
    assert deleted["activities"] == 1

    # 刪除必須「當下即刪」:摘要立即歸零、持股查不到
    summary = client.get("/api/privacy/summary").json()["data"]
    assert all(v == 0 for v in summary.values())
    assert client.get("/api/portfolio/holdings").json()["data"] == []


def test_delete_all_only_touches_own_user(client):
    _seed_user_data(client)
    # 另一個用戶的資料不受影響(X-User-Id 隔離)
    other = {"X-User-Id": "other-user"}
    client.post("/api/portfolio/items", headers=other,
                json={"symbol": "2330", "shares": 500, "cost_price": 800})

    client.delete("/api/privacy/all")

    other_summary = client.get("/api/privacy/summary", headers=other).json()["data"]
    assert other_summary["holdings"] == 1
