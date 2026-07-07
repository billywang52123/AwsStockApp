import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from app.db.database import Base
from app.services.services import AchievementService
from app.services.achievements_catalog import ACHIEVEMENTS

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

def test_catalog_listing_and_unlocking(db_session):
    service = AchievementService(db_session)

    # 1. Fetch achievements -> full catalog, all locked
    data = service.get_achievements()
    assert len(data) == len(ACHIEVEMENTS)
    assert all(a["is_unlocked"] is False for a in data)
    assert all("category" in a and "rarity" in a for a in data)

    # 2. Hidden achievements are masked while locked
    hidden = [a for a in data if a["is_hidden"]]
    assert hidden and all(a["title"] == "？？？" for a in hidden)

    # 3. Trigger an event-based unlock
    assert service.trigger_unlock("IMPORT_FIRST_OCR") is True
    # Unlocking twice is a no-op
    assert service.trigger_unlock("IMPORT_FIRST_OCR") is False
    # Unknown keys are rejected
    assert service.trigger_unlock("NOT_A_REAL_KEY") is False

    updated = {a["achievement_key"]: a for a in service.get_achievements()}
    assert updated["IMPORT_FIRST_OCR"]["is_unlocked"] is True
    assert updated["IMPORT_FIRST_OCR"]["unlocked_at"] is not None

def test_hidden_achievement_revealed_after_unlock(db_session):
    service = AchievementService(db_session)
    assert service.trigger_unlock("IMPORT_OCR_SAD") is True

    data = {a["achievement_key"]: a for a in service.get_achievements()}
    assert data["IMPORT_OCR_SAD"]["title"] == "OCR 也看不懂你的慘況"
    assert data["IMPORT_OCR_SAD"]["is_unlocked"] is True

def test_evaluator_unlocks_from_portfolio(db_session):
    from datetime import date
    from app.models.stock import Stock
    from app.models.stock_daily_price import StockDailyPrice
    from app.models.portfolio import PortfolioItem

    # Seed: TSMC bought at 500, now 1000 (+100%), up 2% today
    db_session.add(Stock(symbol="2330", name="台積電", market="TW", industry="半導體"))
    db_session.add(StockDailyPrice(symbol="2330", trade_date=date.today(), close_price=1000.0, change_percent=2.0))
    db_session.add(PortfolioItem(user_id="demo-user", symbol="2330", cost_price=500.0, shares=1000))
    db_session.commit()

    service = AchievementService(db_session)
    newly = service.evaluate("demo-user")
    keys = {a["achievement_key"] for a in newly}

    assert "PNL_UP_100" in keys          # 買豪宅 (+100%)
    assert "THEME_TSMC" in keys          # 護國神山巡禮
    assert "SINGLE_UP_100" in keys       # 這張有神明保佑
    assert "COMBO_ALL_RED" in keys       # 滿江紅（唯一持股上漲）
    assert "SINGLE_CORE_50" in keys      # 我的核心資產（100% 佔比）

    # Second evaluation returns nothing new
    assert service.evaluate("demo-user") == []
