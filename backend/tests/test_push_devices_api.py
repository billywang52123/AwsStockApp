import sys
from pathlib import Path

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine, select
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

backend_dir = Path(__file__).resolve().parent.parent
sys.path.append(str(backend_dir))

from app.db.base import Base
from app.db.database import get_db
from app.main import app
from app.models.push_device import PushDevice


engine = create_engine(
    "sqlite:///:memory:",
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
        db.close()
        Base.metadata.drop_all(bind=engine)


@pytest.fixture()
def client(db_session):
    def override_get_db():
        yield db_session

    app.dependency_overrides[get_db] = override_get_db
    yield TestClient(app)
    del app.dependency_overrides[get_db]


TOKEN = "a" * 64


def test_register_stores_token_before_sns_is_configured(client, db_session):
    response = client.post(
        "/api/push-devices",
        json={"device_token": TOKEN, "platform": "ios", "environment": "sandbox"},
    )
    assert response.status_code == 200
    data = response.json()["data"]
    assert data["registration_status"] == "pending_sns_configuration"

    stored = db_session.scalars(select(PushDevice)).one()
    assert stored.user_id == "demo-user"
    assert stored.device_token == TOKEN
    assert stored.device_token_hash != TOKEN
    assert stored.sns_endpoint_arn is None


def test_register_is_idempotent(client, db_session):
    body = {"device_token": TOKEN, "platform": "ios", "environment": "sandbox"}
    first = client.post("/api/push-devices", json=body).json()["data"]
    second = client.post("/api/push-devices", json=body).json()["data"]
    assert first["id"] == second["id"]
    assert len(db_session.scalars(select(PushDevice)).all()) == 1


def test_device_is_scoped_to_authenticated_user(client):
    client.post("/api/push-devices", json={"device_token": TOKEN})
    other = client.get(
        "/api/push-devices", headers={"X-User-Id": "someone-else"}
    ).json()["data"]
    assert other == []


def test_delete_requires_owner(client):
    device = client.post("/api/push-devices", json={"device_token": TOKEN}).json()["data"]
    denied = client.delete(
        f"/api/push-devices/{device['id']}",
        headers={"X-User-Id": "someone-else"},
    )
    assert denied.status_code == 404
    assert client.delete(f"/api/push-devices/{device['id']}").status_code == 200


# ---- 發送(send_to_user / style shift 觸發) --------------------------------


class StubSns:
    """publish 回傳預先排好的結果並記錄呼叫,不碰 AWS。"""

    def __init__(self, outcomes=None):
        self.outcomes = list(outcomes or [])
        self.calls = []

    def ensure_endpoint(self, **kwargs):
        return "arn:aws:sns:us-east-1:000000000000:endpoint/APNS/stub/abc"

    def delete_endpoint(self, endpoint_arn):
        pass

    def publish(self, endpoint_arn, *, title, body, data=None):
        self.calls.append({"arn": endpoint_arn, "title": title, "body": body, "data": data})
        return self.outcomes.pop(0) if self.outcomes else "sent"


def _register_device(db_session, sns, user_id="demo-user", token=TOKEN):
    from app.services.push_device_service import PushDeviceService

    service = PushDeviceService(db_session, sns=sns)
    service.register(user_id=user_id, device_token=token, platform="ios", environment="sandbox")
    return service


def test_send_to_user_publishes_to_registered_devices(db_session):
    sns = StubSns()
    service = _register_device(db_session, sns)

    sent = service.send_to_user(
        "demo-user", title="測試", body="內容", data={"type": "style_shift"}
    )

    assert sent == 1
    assert sns.calls[-1]["data"] == {"type": "style_shift"}


def test_send_to_user_disables_dead_endpoint(db_session):
    from sqlalchemy import select as sa_select

    sns = StubSns(outcomes=["disabled"])
    service = _register_device(db_session, sns)

    sent = service.send_to_user("demo-user", title="測試", body="內容")

    assert sent == 0
    stored = db_session.scalars(sa_select(PushDevice)).one()
    assert stored.enabled is False


def test_test_push_endpoint_returns_sent_count(client):
    # 未設 SNS ARN 時裝置沒有 endpoint,send 會安全地回 0 而不碰 AWS
    client.post("/api/push-devices", json={"device_token": TOKEN})
    response = client.post("/api/push-devices/test")
    assert response.status_code == 200
    assert response.json()["data"]["sent"] == 0


def test_style_shift_pushes_only_on_holding_trigger_and_style_change(db_session, monkeypatch):
    from app.services.investment_profile_service import InvestmentProfileService

    pushes = []

    def fake_send(self, user_id, *, title, body, data=None):
        pushes.append({"user_id": user_id, "title": title, "body": body, "data": data})
        return 1

    from app.services.push_device_service import PushDeviceService

    monkeypatch.setattr(PushDeviceService, "send_to_user", fake_send)

    service = InvestmentProfileService(db_session)

    class PreviousSnapshot:
        observed_style_code = "diversified_balancer"
        observed_style_label = "分散平衡型"

    changed = {"code": "focused_growth", "label": "集中成長型"}
    unchanged = {"code": "diversified_balancer", "label": "分散平衡型"}

    # 持股觸發 + 風格改變 → 發推播,且 payload 帶 style_shift 深連結型別
    service._notify_style_shift("u1", "holding_buy", PreviousSnapshot(), changed)
    assert len(pushes) == 1
    assert pushes[0]["data"] == {"type": "style_shift"}
    assert "集中成長型" in pushes[0]["body"]

    # 風格沒變 / 非持股觸發 / 首次快照 → 都不發
    service._notify_style_shift("u1", "holding_buy", PreviousSnapshot(), unchanged)
    service._notify_style_shift("u1", "questionnaire", PreviousSnapshot(), changed)
    service._notify_style_shift("u1", "manual_refresh", PreviousSnapshot(), changed)
    service._notify_style_shift("u1", "holding_buy", None, changed)
    assert len(pushes) == 1

