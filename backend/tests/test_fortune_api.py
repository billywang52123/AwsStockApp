"""每日御神籤 API 測試(spec 第十輪 12a–12d)。"""
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
from app.services import fortune_service
from app.services.fortune_service import (
    _level_value, _chinese_number, current_session, LEVELS, TAIPEI,
)

SQLALCHEMY_DATABASE_URL = "sqlite:///:memory:"
engine = create_engine(
    SQLALCHEMY_DATABASE_URL,
    connect_args={"check_same_thread": False},
    poolclass=StaticPool
)
TestingSessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

BANNED_WORDS = ("建議", "買進", "賣出", "加碼", "減碼", "停損", "停利", "攤平", "進場", "出場")


@pytest.fixture()
def db_session():
    Base.metadata.create_all(bind=engine)
    db = TestingSessionLocal()

    today = date.today()
    db.add_all([
        Stock(symbol="2330", name="台積電", market="TW", industry="半導體"),
        Stock(symbol="2454", name="聯發科", market="TW", industry="IC設計"),
        Stock(symbol="0050", name="元大台灣50", market="TW", industry="ETF"),
        StockDailyPrice(symbol="2330", trade_date=today, close_price=980.0, change_percent=1.4, volume=1000),
        StockDailyPrice(symbol="2454", trade_date=today, close_price=1250.0, change_percent=0.3, volume=500),
        StockDailyPrice(symbol="0050", trade_date=today, close_price=185.0, change_percent=-0.4, volume=800),
        MarketIndexDaily(index_code="TAIEX", trade_date=today, close_price=22000.0, change_percent=0.6),
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


@pytest.fixture()
def day_session(monkeypatch):
    """固定在 14:00(日盤時段),測試不受實際跑的時刻影響。"""
    from datetime import datetime
    monkeypatch.setattr(fortune_service, "_now_taipei",
                        lambda: datetime(2026, 7, 10, 14, 0, tzinfo=TAIPEI))


def _freeze(monkeypatch, hour, minute=0, day=10):
    from datetime import datetime
    monkeypatch.setattr(fortune_service, "_now_taipei",
                        lambda: datetime(2026, 7, day, hour, minute, tzinfo=TAIPEI))


# ── 規則單元:六級對映與中文數字 ─────────────────────────────

def test_level_value_thresholds():
    assert LEVELS[_level_value(3.0) - 1] == "大吉"
    assert LEVELS[_level_value(1.5) - 1] == "吉"
    assert LEVELS[_level_value(0.2) - 1] == "小吉"
    assert LEVELS[_level_value(-0.5) - 1] == "小凶"
    assert LEVELS[_level_value(-1.8) - 1] == "凶"
    assert LEVELS[_level_value(-3.5) - 1] == "大凶"


def test_chinese_number():
    assert _chinese_number(14) == "十四"
    assert _chinese_number(7) == "七"
    assert _chinese_number(21) == "二十一"
    assert _chinese_number(100) == "一百"


# ── /fortune ─────────────────────────────────────────────────

def test_today_before_draw_is_null(client, day_session):
    response = client.get("/api/fortune/today")
    assert response.status_code == 200
    assert response.json()["data"] is None


def test_draw_fortune_structure(client, day_session, db_session):
    seed_portfolio(db_session)
    response = client.post("/api/fortune/draw")
    assert response.status_code == 201
    data = response.json()["data"]

    assert 1 <= data["stick_number"] <= 100
    assert data["stick_label"].startswith("第") and data["stick_label"].endswith("籤")
    assert data["overall_level"] in LEVELS
    assert data["already_drawn"] is False

    # 三欄位:持股與狀態 / 說明 / 注意事項
    assert len(data["holdings"]) == 3
    for h in data["holdings"]:
        assert h["level"] in LEVELS
        assert len(h["comment"]) > 0
    assert len(data["summary"]) > 0
    assert len(data["stance"]) > 0
    assert 1 <= len(data["notices"]) <= 3

    # 2330 +1.4% → 吉;2454 +0.3% → 小吉;0050 -0.4% → 小凶
    by_symbol = {h["symbol"]: h["level"] for h in data["holdings"]}
    assert by_symbol == {"2330": "吉", "2454": "小吉", "0050": "小凶"}
    # 加權綜合(2330 權重最大)落在偏吉區
    assert data["overall_level"] in ("小吉", "吉")


def test_draw_is_idempotent_per_day(client, day_session, db_session):
    seed_portfolio(db_session)
    first = client.post("/api/fortune/draw").json()["data"]
    second = client.post("/api/fortune/draw").json()["data"]
    assert second["already_drawn"] is True
    assert second["stick_number"] == first["stick_number"]
    assert second["summary"] == first["summary"]

    today = client.get("/api/fortune/today").json()["data"]
    assert today["stick_number"] == first["stick_number"]


def test_force_redraw_uses_current_holdings(client, day_session, db_session):
    """force=true:丟棄今日籤,依「當下」持股重新計算(重抽測試用)。"""
    first = client.post("/api/fortune/draw").json()["data"]
    assert first["holdings"] == []          # 無持股時求得

    seed_portfolio(db_session)
    same = client.post("/api/fortune/draw").json()["data"]
    assert same["already_drawn"] is True    # 不帶 force 仍回同一支
    assert same["holdings"] == []

    redrawn = client.post("/api/fortune/draw?force=true").json()["data"]
    assert redrawn["already_drawn"] is False
    assert len(redrawn["holdings"]) == 3    # 重抽後反映當下持股

    today = client.get("/api/fortune/today").json()["data"]
    assert len(today["holdings"]) == 3      # 今日籤已被新的取代


def test_no_banned_words(client, day_session, db_session):
    seed_portfolio(db_session)
    data = client.post("/api/fortune/draw").json()["data"]
    all_text = data["summary"] + data["stance"] + data["stance_note"] \
        + "".join(data["notices"]) + "".join(h["comment"] for h in data["holdings"]) \
        + data["level_note"]
    for banned in BANNED_WORDS:
        assert banned not in all_text, f"籤詩文字出現禁字:{banned}"


def test_draw_without_holdings(client, day_session):
    data = client.post("/api/fortune/draw").json()["data"]
    assert data["overall_level"] == "小吉"
    assert data["holdings"] == []
    assert len(data["summary"]) > 0


def test_user_isolation(client, day_session, db_session):
    seed_portfolio(db_session)
    client.post("/api/fortune/draw")
    other = client.get("/api/fortune/today", headers={"X-User-Id": "someone-else"})
    assert other.json()["data"] is None


# ── 日盤 / 夜盤 各一支 ────────────────────────────────────────

def test_current_session_windows():
    from datetime import datetime, date as ddate
    # 13:30 起 → 當日日盤;跨午夜到 05:00 前仍是前一日的日盤
    assert current_session(datetime(2026, 7, 10, 13, 30, tzinfo=TAIPEI)) == (ddate(2026, 7, 10), "day")
    assert current_session(datetime(2026, 7, 10, 23, 50, tzinfo=TAIPEI)) == (ddate(2026, 7, 10), "day")
    assert current_session(datetime(2026, 7, 11, 4, 59, tzinfo=TAIPEI)) == (ddate(2026, 7, 10), "day")
    # 05:00(美股收盤)起 → 當日夜盤,直到 13:30
    assert current_session(datetime(2026, 7, 11, 5, 0, tzinfo=TAIPEI)) == (ddate(2026, 7, 11), "night")
    assert current_session(datetime(2026, 7, 11, 13, 29, tzinfo=TAIPEI)) == (ddate(2026, 7, 11), "night")


def test_day_and_night_sessions_draw_separately(client, db_session, monkeypatch):
    """日盤抽一支後,到夜盤時段可再抽新的一支;各時段內冪等。"""
    seed_portfolio(db_session)

    # 7/10 14:00 抽日盤籤
    _freeze(monkeypatch, hour=14, day=10)
    day_draw = client.post("/api/fortune/draw").json()["data"]
    assert day_draw["session"] == "day"
    assert day_draw["already_drawn"] is False

    # 同一晚 23:00 還是同一支日盤籤
    _freeze(monkeypatch, hour=23, day=10)
    same = client.post("/api/fortune/draw").json()["data"]
    assert same["already_drawn"] is True
    assert same["stick_number"] == day_draw["stick_number"]

    # 次日 03:00(05:00 前)仍屬前一日日盤,today 回同一支
    _freeze(monkeypatch, hour=3, day=11)
    today = client.get("/api/fortune/today").json()["data"]
    assert today["stick_number"] == day_draw["stick_number"]

    # 次日 06:00 進入夜盤時段:還沒抽 → today 為 null,可抽新的一支
    _freeze(monkeypatch, hour=6, day=11)
    assert client.get("/api/fortune/today").json()["data"] is None
    night_draw = client.post("/api/fortune/draw").json()["data"]
    assert night_draw["session"] == "night"
    assert night_draw["already_drawn"] is False

    # 夜盤時段內冪等
    night_again = client.post("/api/fortune/draw").json()["data"]
    assert night_again["already_drawn"] is True
    assert night_again["stick_number"] == night_draw["stick_number"]
