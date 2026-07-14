import math

from fastapi import FastAPI, Request
from fastapi.encoders import jsonable_encoder
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
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
from app.models.watchlist import Watchlist, WatchlistItem
from app.models.fortune import FortuneResultModel
from app.models.daily_pack import DailyPackModel
from app.models.push_device import PushDevice
from app.models.app_setting import AppSetting

# Routes
from app.api.routes import (
    auth, portfolio, stocks, anxiety, daily_summary, cards, market, recommendations, reminders, admin_import, achievements, scan, analysis, holdings, privacy, watchlists, fortune, push_devices, pack, admin_sim
)
from app.db.migrations import run_light_migrations
from app.db.database import SessionLocal
from app.services import sim_clock

Base.metadata.create_all(bind=engine)
run_light_migrations(engine)

# 啟動時載入模擬今天覆寫(若有),讓 effective_trade_date() 無 session 也能讀
with SessionLocal() as _startup_db:
    sim_clock.load_from_db(_startup_db)

app = FastAPI(
    title=settings.PROJECT_NAME,
    description="Backend API for beginner investor emotional companion iOS App",
    version="0.1.0"
)

def _json_safe(obj):
    """422 錯誤內容會夾帶原始輸入值;NaN/Infinity 沒轉字串會讓錯誤回應本身序列化失敗變 500。"""
    if isinstance(obj, float) and not math.isfinite(obj):
        return str(obj)
    if isinstance(obj, dict):
        return {k: _json_safe(v) for k, v in obj.items()}
    if isinstance(obj, (list, tuple)):
        return [_json_safe(v) for v in obj]
    return obj


@app.exception_handler(RequestValidationError)
async def validation_exception_handler(request: Request, exc: RequestValidationError):
    return JSONResponse(
        status_code=422,
        content={"detail": _json_safe(jsonable_encoder(exc.errors()))},
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
app.include_router(privacy.router, prefix=settings.API_V1_STR)
app.include_router(watchlists.router, prefix=settings.API_V1_STR)
app.include_router(fortune.router, prefix=settings.API_V1_STR)
app.include_router(pack.router, prefix=settings.API_V1_STR)
app.include_router(push_devices.router, prefix=settings.API_V1_STR)
app.include_router(admin_sim.router, prefix=settings.API_V1_STR)

@app.get("/health", tags=["Health"])
def health_check():
    return {"status": "ok", "project": settings.PROJECT_NAME}
