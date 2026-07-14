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

