"""spec 08 語音輸入持股:POST /portfolio/holdings/parse-voice 解析與驗證。

LLM(Bedrock/OpenAI)一律 mock 掉,測的是解析後的代號驗證、低信心退回、
安撫失敗文案與輸入防呆。
"""

import sys
from pathlib import Path
from unittest.mock import patch

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
    db.add(Stock(symbol="2891", name="中信金", market="TW", industry="金融"))
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


class _FakeLLM:
    def __init__(self, payload=None, error=None):
        self._payload = payload
        self._error = error

    def converse_json(self, **kwargs):
        if self._error:
            raise self._error
        return self._payload


def _post(client, text="幫我加台積電兩張成本九百八"):
    return client.post("/api/portfolio/holdings/parse-voice", json={"text": text})


def test_parse_voice_resolves_symbols(client):
    """LLM 給的代號逐檔驗證通過 → high confidence + 換算註記原樣帶回."""
    payload = {"items": [
        {"mention": "台積電", "symbol": "2330", "shares": 2000, "cost_price": 980,
         "note": "『兩張』= 2,000 股 ·『九百八』= 成本 980 元"},
        {"mention": "中信金", "symbol": "2891", "shares": 300, "cost_price": None, "note": None},
    ]}
    with patch("app.services.voice_holding_parser.get_llm", return_value=_FakeLLM(payload)):
        resp = _post(client, "幫我加台積電兩張成本九百八,還有中信金三百股")
    assert resp.status_code == 200
    data = resp.json()["data"]
    assert data["transcript"].startswith("幫我加台積電")
    assert data["message"] is None
    assert len(data["items"]) == 2
    first, second = data["items"]
    assert first == {
        "symbol": "2330", "name": "台積電", "mention": "台積電",
        "shares": 2000, "cost_price": 980.0,
        "note": "『兩張』= 2,000 股 ·『九百八』= 成本 980 元",
        "confidence": "high",
    }
    assert second["symbol"] == "2891"
    assert second["cost_price"] is None       # 成本選填,不擋加入
    assert second["confidence"] == "high"


def test_parse_voice_name_fallback_when_symbol_missing(client):
    """LLM 沒把握給代號 → 名稱搜尋唯一命中仍可解析成 high."""
    payload = {"items": [
        {"mention": "中信金", "symbol": None, "shares": None, "cost_price": None, "note": None},
    ]}
    with patch("app.services.voice_holding_parser.get_llm", return_value=_FakeLLM(payload)):
        resp = _post(client, "加一下中信金")
    item = resp.json()["data"]["items"][0]
    assert item["symbol"] == "2891"
    assert item["confidence"] == "high"
    assert item["shares"] is None             # 沒提到股數不猜


def test_parse_voice_unresolved_returns_low_confidence(client):
    """對不到台股代號 → 保留原話、low confidence(19c 金色卡),不整包失敗."""
    payload = {"items": [
        {"mention": "台積電", "symbol": "2330", "shares": 1000, "cost_price": None, "note": None},
        {"mention": "隔壁老王推薦的那檔", "symbol": None, "shares": 500, "cost_price": None, "note": None},
    ]}
    with patch("app.services.voice_holding_parser.get_llm", return_value=_FakeLLM(payload)):
        resp = _post(client)
    items = resp.json()["data"]["items"]
    assert len(items) == 2
    low = items[1]
    assert low["symbol"] is None
    assert low["mention"] == "隔壁老王推薦的那檔"
    assert low["confidence"] == "low"


def test_parse_voice_llm_failure_returns_soothing_message(client):
    """LLM 掛掉不回 5xx:空 items + 安撫文案,由前端引導重說/手動(spec 08 鐵則)."""
    with patch("app.services.voice_holding_parser.get_llm",
               return_value=_FakeLLM(error=RuntimeError("bedrock down"))):
        resp = _post(client)
    assert resp.status_code == 200
    data = resp.json()["data"]
    assert data["items"] == []
    assert data["message"] == "沒聽清楚,再說一次試試"


def test_parse_voice_empty_and_irrelevant_text(client):
    """空白句直接安撫回覆(不打 LLM);無關內容 LLM 回空 items 也一樣."""
    resp = _post(client, "   ")
    data = resp.json()["data"]
    assert data["items"] == [] and data["message"]

    with patch("app.services.voice_holding_parser.get_llm",
               return_value=_FakeLLM({"items": []})):
        resp = _post(client, "今天天氣真好")
    data = resp.json()["data"]
    assert data["items"] == [] and data["message"]


def test_parse_voice_sanitizes_bogus_numbers(client):
    """股數/成本超界或非數字 → 當作沒提到(None),不讓髒資料進 19c."""
    payload = {"items": [
        {"mention": "台積電", "symbol": "2330", "shares": -5, "cost_price": "abc",
         "note": None},
    ]}
    with patch("app.services.voice_holding_parser.get_llm", return_value=_FakeLLM(payload)):
        resp = _post(client)
    item = resp.json()["data"]["items"][0]
    assert item["shares"] is None
    assert item["cost_price"] is None


def test_parse_voice_rejects_overlong_text(client):
    """逐字稿超過 500 字由 pydantic 直接擋下(422),不會進 LLM."""
    resp = _post(client, "台" * 501)
    assert resp.status_code == 422
