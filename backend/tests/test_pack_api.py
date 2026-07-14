"""每日抽卡包 + AI 信任系統 API 測試(spec 06 · 15a–15k)。"""
import json
import sys
from datetime import date, datetime, timedelta
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
from app.models.daily_pack import DailyPackModel
from app.services import daily_pack_service
from app.services.daily_pack_service import TAIPEI, pack_trade_date

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


@pytest.fixture()
def afternoon(monkeypatch):
    """固定在今天 15:00(收盤後),卡包交易日 = 今天,對齊種子價格資料。"""
    now = datetime.now(TAIPEI).replace(hour=15, minute=0)
    monkeypatch.setattr(daily_pack_service, "_now_taipei", lambda: now)


def seed_portfolio(db):
    db.add_all([
        PortfolioItem(user_id="demo-user", symbol="2330", cost_price=900.0, shares=3000),
        PortfolioItem(user_id="demo-user", symbol="2454", cost_price=1300.0, shares=500),
        PortfolioItem(user_id="demo-user", symbol="0050", cost_price=170.0, shares=5000),
    ])
    db.commit()


def all_chip_dicts(payload):
    """走訪整包,收集所有出處 chip。"""
    chips = []

    def walk(node):
        if isinstance(node, dict):
            if {"field", "raw_value", "formula", "data_date", "source"} <= set(node.keys()):
                chips.append(node)
            for v in node.values():
                walk(v)
        elif isinstance(node, list):
            for v in node:
                walk(v)

    walk(payload)
    return chips


# ── 交易日邊界 ───────────────────────────────────────────────

def test_pack_trade_date_boundary():
    assert pack_trade_date(datetime(2026, 7, 10, 14, 29, tzinfo=TAIPEI)) == date(2026, 7, 9)
    assert pack_trade_date(datetime(2026, 7, 10, 14, 30, tzinfo=TAIPEI)) == date(2026, 7, 10)


# ── /pack/today ──────────────────────────────────────────────

def test_today_pack_structure(client, db_session, afternoon):
    seed_portfolio(db_session)
    response = client.get("/api/pack/today")
    assert response.status_code == 200
    data = response.json()["data"]

    assert data["holdings_count"] == 3
    assert data["opened"] is False
    assert "萬" in data["total_value_text"]

    # 三張卡固定齊備:事實 / 推論 / 陪伴
    fact = data["fact"]
    assert len(fact["stocks"]) == 3
    assert fact["stocks"][0]["expanded_default"] is True     # 權重最大預設展開
    assert fact["stocks"][0]["symbol"] == "2330"             # 3000 股台積電權重最大
    for s in fact["stocks"]:
        assert len(s["rows"]) == 3
        for row in s["rows"]:
            assert row["chip"]["source"]                     # 每行掛出處 chip

    inference = data["inference"]
    assert len(inference["steps"]) == 3
    assert inference["steps"][2]["glossary"] is not None     # 第 3 步行為財務學名詞小卡
    assert "可能有錯" in inference["caveat"]

    companion = data["companion"]
    assert companion["day_count"] == 1
    assert companion["signature"].startswith("——")

    # why_today 的出處 chips 不為空
    assert len(data["why_today"]["chips"]) == 2


def test_today_pack_idempotent(client, db_session, afternoon):
    seed_portfolio(db_session)
    first = client.get("/api/pack/today").json()["data"]
    second = client.get("/api/pack/today").json()["data"]
    assert first["fact"] == second["fact"]
    assert first["companion"]["text"] == second["companion"]["text"]


def test_no_banned_words(client, db_session, afternoon):
    seed_portfolio(db_session)
    data = client.get("/api/pack/today").json()["data"]
    text = json.dumps(data, ensure_ascii=False)
    for banned in BANNED_WORDS:
        assert banned not in text, f"卡包文字出現禁字:{banned}"


def test_flashcard_requires_hardcoded_event(client, db_session, afternoon):
    """種子資料最大漲幅 1.4%,未達 ±3% 也非新高(只有一天資料)→ 不觸發閃卡。"""
    seed_portfolio(db_session)
    data = client.get("/api/pack/today").json()["data"]
    assert data["fact"]["flashcard"] is None


def test_flashcard_triggers_on_three_percent(client, db_session, afternoon):
    seed_portfolio(db_session)
    price = db_session.query(StockDailyPrice).filter_by(symbol="2454").first()
    price.change_percent = 4.2
    db_session.commit()

    data = client.get("/api/pack/today").json()["data"]
    flash = data["fact"]["flashcard"]
    assert flash is not None
    assert "聯發科" in flash["event_text"]
    assert "3%" in flash["chip"]["formula"]                  # 觸發條件寫死在算式裡


def test_empty_holdings_pack(client, afternoon):
    data = client.get("/api/pack/today").json()["data"]
    assert data["holdings_count"] == 0
    assert data["fact"]["stocks"] == []
    assert len(data["inference"]["steps"]) == 1
    assert len(data["companion"]["text"]) > 0


def test_open_marks_pack(client, db_session, afternoon):
    seed_portfolio(db_session)
    assert client.get("/api/pack/today").json()["data"]["opened"] is False
    assert client.post("/api/pack/open").json()["data"] is True
    assert client.get("/api/pack/today").json()["data"]["opened"] is True


def test_user_isolation(client, db_session, afternoon):
    seed_portfolio(db_session)
    client.get("/api/pack/today")
    client.post("/api/pack/open")
    other = client.get("/api/pack/today", headers={"X-User-Id": "someone-else"}).json()["data"]
    assert other["opened"] is False
    assert other["holdings_count"] == 0     # 持股也隔離


def test_every_chip_has_provenance(client, db_session, afternoon):
    """信任系統核心:所有 chip 都有欄位/原始值/算法/資料日期/來源五欄。"""
    seed_portfolio(db_session)
    data = client.get("/api/pack/today").json()["data"]
    chips = all_chip_dicts(data)
    assert len(chips) >= 12
    for chip in chips:
        for key in ("field", "raw_value", "formula", "data_date", "source"):
            assert chip[key], f"chip 缺 {key}: {chip}"


# ── /pack/shelf ──────────────────────────────────────────────

def test_shelf(client, db_session, afternoon):
    seed_portfolio(db_session)
    client.get("/api/pack/today")   # 產生一包 → 圖鑑 3 張
    data = client.get("/api/pack/shelf").json()["data"]
    assert len(data["packs"]) == 3
    assert data["packs"][0]["symbol"] == "2330"      # 依權重排序
    assert data["collected_count"] == 3
    assert len(data["recent_cards"]) == 3
    assert {c["kind"] for c in data["recent_cards"]} == {"fact", "inference", "companion"}


# ── /pack/weekly-checkup ─────────────────────────────────────

def test_weekly_checkup_reconciles_claims(client, db_session, afternoon):
    """本週稍早存的 claims 用「現在的數據」對帳:說中沒說中都照實呈現。"""
    seed_portfolio(db_session)
    today = pack_trade_date(datetime.now(TAIPEI).replace(hour=15, minute=0))
    weekday = today.weekday()
    if weekday == 0:
        # 週一沒有「本週稍早」,放到今天之前一天仍屬上週 → 用空對帳分支驗證
        data = client.get("/api/pack/weekly-checkup").json()["data"]
        assert data["total_count"] == 1
        assert data["rows"][0]["outcome"] == "miss"
        return

    earlier = today - timedelta(days=1)
    claims = [
        # 會應驗:0050 門檻寫 0.3,最新 |change| = 0.4 ≥ 0.3
        {"kind": "volatility", "statement": "0050 波動可能延續", "symbol": "0050",
         "name": "元大台灣50", "threshold": 0.3, "baseline": -0.4, "date": earlier.isoformat()},
        # 不會應驗:大盤門檻 1%,最新 +0.6%
        {"kind": "market", "statement": "大盤起伏可能放大", "threshold": 1.0,
         "baseline": 1.2, "date": earlier.isoformat()},
    ]
    db_session.add(DailyPackModel(
        user_id="demo-user", trade_date=earlier, opened=True,
        pack_json=json.dumps({"claims": claims}, ensure_ascii=False),
    ))
    db_session.commit()

    data = client.get("/api/pack/weekly-checkup").json()["data"]
    assert data["total_count"] == 2
    assert data["met_count"] == 1
    outcomes = {r["statement"]: r["outcome"] for r in data["rows"]}
    assert outcomes["0050 波動可能延續"] == "met"
    assert outcomes["大盤起伏可能放大"] == "miss"
    # 說錯的照實寫出,不粉飾
    miss_row = next(r for r in data["rows"] if r["outcome"] == "miss")
    assert "說錯" in miss_row["note"] or "未發生" in miss_row["note"]
    assert len(data["tiles"]) == 2
