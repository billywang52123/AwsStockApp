import sys
from pathlib import Path
import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

# Add backend directory to path so imports work correctly
backend_dir = Path(__file__).resolve().parent.parent
sys.path.append(str(backend_dir))

from app.main import app
from app.db.base import Base
from app.db.database import get_db
from app.models.stock import Stock

from sqlalchemy.pool import StaticPool

# Setup Test SQLite Database in-memory
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
    
    # Seed default stock meta so add portfolio succeeds
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
        try:
            yield db_session
        finally:
            pass
            
    app.dependency_overrides[get_db] = override_get_db
    yield TestClient(app)
    del app.dependency_overrides[get_db]

def test_get_portfolio_items_empty(client):
    response = client.get("/api/portfolio/items")
    assert response.status_code == 200
    json_data = response.json()
    assert json_data["success"] is True
    assert json_data["data"] == []

def test_add_and_delete_portfolio_item(client):
    # Add Item
    response = client.post("/api/portfolio/items", json={
        "symbol": "2330"
    })
    assert response.status_code == 201
    json_data = response.json()
    assert json_data["success"] is True
    assert json_data["data"]["symbol"] == "2330"
    
    item_id = json_data["data"]["id"]
    
    # Get Items List
    response = client.get("/api/portfolio/items")
    assert len(response.json()["data"]) == 1
    
    # Delete Item
    response = client.delete(f"/api/portfolio/items/{item_id}")
    assert response.status_code == 200
    assert response.json()["success"] is True
    
    # Get Items List again
    response = client.get("/api/portfolio/items")
    assert len(response.json()["data"]) == 0
