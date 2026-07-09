from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session
from app.core.auth import get_current_user_id
from app.db.database import get_db
from app.schemas.common_schema import ApiResponse
from app.schemas.watchlist_schema import RecommendedStockRead
from app.services.services import StockService
from app.services.watchlist_service import WatchlistService

router = APIRouter(prefix="/recommendations", tags=["Recommendations"])

@router.get("/stocks", response_model=ApiResponse[list[RecommendedStockRead]])
def get_recommendations(symbol: str = Query(..., description="The symbol to base recommendations on"),
                        db: Session = Depends(get_db),
                        user_id: str = Depends(get_current_user_id)):
    """推薦股票;已在使用者觀察清單中的掛星標資訊(11g)。"""
    service = StockService(db)
    recs = service.get_recommendations(symbol)
    membership = WatchlistService(db).membership_map(user_id)
    items = []
    for stock in recs:
        wl = membership.get(stock.symbol)
        items.append(RecommendedStockRead(
            symbol=stock.symbol, name=stock.name, market=stock.market,
            industry=stock.industry,
            in_watchlist=wl is not None,
            watchlist_id=wl[0] if wl else None,
            watchlist_name=wl[1] if wl else None,
        ))
    return ApiResponse(success=True, data=items)
