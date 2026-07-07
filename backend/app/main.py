from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from app.core.config import settings

# Database initializers
from app.db.database import engine, Base
from app.models.stock import Stock
from app.models.portfolio import PortfolioItem
from app.models.stock_daily_price import StockDailyPrice
from app.models.market_index import MarketIndexDaily
from app.models.reminder import ReminderSettingModel
from app.models.card_result import CardResultModel
from app.models.achievement import AchievementModel
from app.models.holding_activity import HoldingActivityModel

# Routes
from app.api.routes import (
    auth, portfolio, stocks, anxiety, daily_summary, cards, market, recommendations, reminders, admin_import, achievements, scan, analysis, holdings
)
from app.db.migrations import run_light_migrations

Base.metadata.create_all(bind=engine)
run_light_migrations(engine)

app = FastAPI(
    title=settings.PROJECT_NAME,
    description="Backend API for beginner investor emotional companion iOS App",
    version="0.1.0"
)

# CORS — use specific origins, not wildcard
allowed_origins = [o.strip() for o in settings.ALLOWED_ORIGINS.split(",") if o.strip()]
app.add_middleware(
    CORSMiddleware,
    allow_origins=allowed_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(auth.router, prefix=settings.API_V1_STR)
app.include_router(portfolio.router, prefix=settings.API_V1_STR)
app.include_router(stocks.router, prefix=settings.API_V1_STR)
app.include_router(anxiety.router, prefix=settings.API_V1_STR)
app.include_router(daily_summary.router, prefix=settings.API_V1_STR)
app.include_router(cards.router, prefix=settings.API_V1_STR)
app.include_router(market.router, prefix=settings.API_V1_STR)
app.include_router(recommendations.router, prefix=settings.API_V1_STR)
app.include_router(reminders.router, prefix=settings.API_V1_STR)
app.include_router(admin_import.router, prefix=settings.API_V1_STR)
app.include_router(achievements.router, prefix=settings.API_V1_STR)
app.include_router(scan.router, prefix=settings.API_V1_STR)
app.include_router(analysis.router, prefix=settings.API_V1_STR)
app.include_router(holdings.router, prefix=settings.API_V1_STR)

@app.get("/health", tags=["Health"])
def health_check():
    return {"status": "ok", "project": settings.PROJECT_NAME}
