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
from app.core.config import settings
from app.core.security import create_session_token

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
    app.dependency_overrides.clear()


GUEST_ID = "guest-123e4567-e89b-42d3-a456-426614174000"


class TestGuestAuth:
    def test_guest_auth_issues_token_for_existing_id(self, client):
        res = client.post("/api/auth/guest", json={"guest_id": GUEST_ID})
        assert res.status_code == 200
        data = res.json()["data"]
        assert data["user_id"] == GUEST_ID
        assert data["token_type"] == "bearer"
        assert data["access_token"]

    def test_guest_auth_generates_id_when_missing(self, client):
        res = client.post("/api/auth/guest", json={})
        assert res.status_code == 200
        data = res.json()["data"]
        assert data["user_id"].startswith("guest-")
        assert data["access_token"]

    def test_guest_auth_rejects_arbitrary_id(self, client):
        # Only guest-<uuid> shaped ids are accepted — you can't mint a token
        # for someone else's apple-/google- account through the guest door.
        res = client.post("/api/auth/guest", json={"guest_id": "apple-somebody"})
        assert res.status_code == 400


class TestBearerAuth:
    def test_bearer_token_identifies_user(self, client):
        token = client.post(
            "/api/auth/guest", json={"guest_id": GUEST_ID}
        ).json()["data"]["access_token"]

        res = client.get(
            "/api/portfolio/items",
            headers={"Authorization": f"Bearer {token}"}
        )
        assert res.status_code == 200
        assert res.json()["success"] is True

    def test_invalid_bearer_token_is_rejected(self, client):
        res = client.get(
            "/api/portfolio/items",
            headers={"Authorization": "Bearer not-a-real-token"}
        )
        assert res.status_code == 401

    def test_bearer_takes_precedence_over_header(self, client, db_session):
        """A valid token wins even if a conflicting X-User-Id is sent."""
        from app.models.stock import Stock
        db_session.add(Stock(symbol="2330", name="台積電", market="TW", industry="半導體"))
        db_session.commit()

        token = create_session_token("user-a")
        client.post(
            "/api/portfolio/items",
            json={"symbol": "2330", "cost_price": 500, "shares": 1000},
            headers={"Authorization": f"Bearer {token}", "X-User-Id": "user-b"},
        )

        res_a = client.get("/api/portfolio/items", headers={"Authorization": f"Bearer {token}"})
        res_b = client.get("/api/portfolio/items", headers={"X-User-Id": "user-b"})
        assert len(res_a.json()["data"]) == 1
        assert len(res_b.json()["data"]) == 0


class TestLegacyHeaderSwitch:
    def test_legacy_header_allowed_by_default(self, client):
        res = client.get("/api/portfolio/items", headers={"X-User-Id": "legacy-user"})
        assert res.status_code == 200

    def test_legacy_header_blocked_when_disabled(self, client, monkeypatch):
        monkeypatch.setattr(settings, "ALLOW_LEGACY_HEADER_AUTH", False)
        res = client.get("/api/portfolio/items", headers={"X-User-Id": "legacy-user"})
        assert res.status_code == 401

    def test_bearer_still_works_when_legacy_disabled(self, client, monkeypatch):
        monkeypatch.setattr(settings, "ALLOW_LEGACY_HEADER_AUTH", False)
        token = create_session_token(GUEST_ID)
        res = client.get(
            "/api/portfolio/items",
            headers={"Authorization": f"Bearer {token}"}
        )
        assert res.status_code == 200


class TestOAuthEndpoints:
    def test_apple_rejects_garbage_token(self, client):
        res = client.post("/api/auth/apple", json={"identity_token": "garbage"})
        assert res.status_code == 401

    def test_google_rejects_garbage_token(self, client):
        res = client.post("/api/auth/google", json={"id_token": "garbage"})
        assert res.status_code == 401


class TestAdminKey:
    def test_admin_endpoints_disabled_without_key(self, client, monkeypatch):
        monkeypatch.setattr(settings, "ADMIN_API_KEY", None)
        res = client.post(
            "/api/admin/import/stocks",
            headers={"X-Admin-Key": "anything"},
            files={"file": ("stocks.csv", b"symbol,name\n", "text/csv")},
        )
        assert res.status_code == 403

    def test_admin_endpoints_reject_wrong_key(self, client, monkeypatch):
        monkeypatch.setattr(settings, "ADMIN_API_KEY", "correct-key")
        res = client.post(
            "/api/admin/import/stocks",
            headers={"X-Admin-Key": "wrong-key"},
            files={"file": ("stocks.csv", b"symbol,name\n", "text/csv")},
        )
        assert res.status_code == 403
