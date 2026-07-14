"""模擬時鐘測試:覆寫「今天」→ effective_trade_date 與 API 一起移動。"""
import sys
from datetime import date, datetime
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
from app.models.app_setting import AppSetting  # noqa: F401 (確保建表)
from app.services import sim_clock
from app.services.cmoney_service import (
    effective_trade_date, simulated_target, TAIPEI,
)

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
    try:
        yield db
    finally:
        sim_clock.clear_override(db)  # 別讓覆寫外洩到其他測試
        db.close()
        Base.metadata.drop_all(bind=engine)


@pytest.fixture()
def client(db_session):
    def override_get_db():
        yield db_session

    app.dependency_overrides[get_db] = override_get_db
    yield TestClient(app)
    del app.dependency_overrides[get_db]


@pytest.fixture(autouse=True)
def _reset_override():
    # 每個測試前後都確保記憶體覆寫是乾淨的
    sim_clock._override = None
    yield
    sim_clock._override = None


def test_no_override_uses_real_time():
    assert sim_clock.get_override() is None
    # 帶明確 now 時忽略覆寫,照 14:30 規則
    assert effective_trade_date(datetime(2026, 7, 10, 14, 29, tzinfo=TAIPEI)) == date(2026, 7, 9)
    assert effective_trade_date(datetime(2026, 7, 10, 14, 30, tzinfo=TAIPEI)) == date(2026, 7, 10)


def test_override_shifts_effective_date(db_session):
    sim_clock.set_override(db_session, date(2026, 3, 15))
    assert sim_clock.get_override() == date(2026, 3, 15)
    # 無明確 now → 直接回覆寫值
    assert effective_trade_date() == date(2026, 3, 15)
    # 模擬交易日 = 今天 − 1 年
    assert simulated_target(effective_trade_date()) == date(2025, 3, 15)
    # 明確 now 仍不受覆寫影響(單元測試路徑)
    assert effective_trade_date(datetime(2026, 7, 10, 15, 0, tzinfo=TAIPEI)) == date(2026, 7, 10)


def test_override_persisted_and_reloaded(db_session):
    sim_clock.set_override(db_session, date(2026, 1, 20))
    # 模擬重啟:清掉記憶體再從 DB 載入
    sim_clock._override = None
    assert sim_clock.get_override() is None
    reloaded = sim_clock.load_from_db(db_session)
    assert reloaded == date(2026, 1, 20)
    assert effective_trade_date() == date(2026, 1, 20)


def test_clear_override(db_session):
    sim_clock.set_override(db_session, date(2026, 5, 1))
    sim_clock.clear_override(db_session)
    assert sim_clock.get_override() is None
    assert db_session.get(AppSetting, sim_clock.SETTING_KEY) is None


def test_api_get_set_clear(client):
    # 初始:無覆寫
    data = client.get("/api/admin/sim-date").json()["data"]
    assert data["overridden"] is False

    # 設定模擬今天
    resp = client.put("/api/admin/sim-date", json={"date": "2026-03-15"}).json()
    assert resp["success"] is True
    d = resp["data"]
    assert d["overridden"] is True
    assert d["effective_today"] == "2026-03-15"
    assert d["simulated_trade_date"] == "2025-03-15"
    # SQLite 無 raw schema → CMoney 不可用,resolved 為 null
    assert d["data_available"] is False
    assert d["resolved_data_date"] is None

    # 清除
    cleared = client.delete("/api/admin/sim-date").json()["data"]
    assert cleared["overridden"] is False


def test_api_rejects_bad_date(client):
    assert client.put("/api/admin/sim-date", json={"date": "not-a-date"}).status_code == 422
