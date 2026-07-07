import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from app.db.database import Base
from app.services.services import AchievementService
from app.models.achievement import AchievementModel

@pytest.fixture
def db_session():
    engine = create_engine("sqlite:///:memory:")
    SessionLocal = sessionmaker(bind=engine)
    Base.metadata.create_all(bind=engine)
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

def test_achievements_seeding_and_unlocking(db_session):
    service = AchievementService(db_session)
    # 1. Fetch achievements -> should seed 4 defaults
    data = service.get_achievements()
    assert len(data) == 4
    assert data[0]["achievement_key"] == "CALM_BEGINNER"
    assert data[0]["is_unlocked"] is False
    
    # 2. Trigger unlock
    unlocked = service.trigger_unlock("CALM_BEGINNER")
    assert unlocked is True
    
    # 3. Check again -> should be unlocked
    updated_data = service.get_achievements()
    assert updated_data[0]["achievement_key"] == "CALM_BEGINNER"
    assert updated_data[0]["is_unlocked"] is True
    assert updated_data[0]["unlocked_at"] is not None
