from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from app.db.database import get_db
from app.schemas.common_schema import ApiResponse
from app.schemas.stock_schema import StockRead, StockDailyPriceRead
from app.services.services import StockService

router = APIRouter(prefix="/stocks", tags=["Stocks"])

@router.get("/search", response_model=ApiResponse[list[StockRead]])
def search_stocks(keyword: str = "", db: Session = Depends(get_db)):
    service = StockService(db)
    results = service.search_stocks(keyword)
    return ApiResponse(success=True, data=results)

@router.get("/{symbol}/daily", response_model=ApiResponse[StockDailyPriceRead])
def get_daily_price(symbol: str, db: Session = Depends(get_db)):
    service = StockService(db)
    price = service.get_daily_price(symbol)
    if not price:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Price data for {symbol} not found"
        )
    return ApiResponse(success=True, data=price)

@router.get("/{symbol}/summary", response_model=ApiResponse[str])
def get_stock_summary(symbol: str, db: Session = Depends(get_db)):
    service = StockService(db)
    price = service.get_daily_price(symbol)
    if not price:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Stock data not found for {symbol}"
        )
    change = float(price.change_percent)
    if change < -2.0:
        msg = f"今天下跌 {abs(change)}%，主要受板塊震盪影響，非個股營運惡化。建議觀察，免焦慮。"
    elif change < 0:
        msg = f"今天小幅調整 {abs(change)}%，屬於正常震盪，不用擔心。"
    else:
        msg = f"今天上漲 {change}%，走勢強勁，為持股情緒提供良好支撐。"
    return ApiResponse(success=True, data=msg)
