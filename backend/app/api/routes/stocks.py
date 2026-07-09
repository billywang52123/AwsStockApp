from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from app.db.database import get_db
from app.schemas.common_schema import ApiResponse
from app.schemas.stock_schema import StockRead, StockDailyPriceRead, AiScreenResult
from app.services.services import StockService

router = APIRouter(prefix="/stocks", tags=["Stocks"])

@router.get("/search", response_model=ApiResponse[list[StockRead]])
def search_stocks(keyword: str = "", db: Session = Depends(get_db)):
    service = StockService(db)
    results = service.search_stocks(keyword)
    return ApiResponse(success=True, data=results)

@router.get("/ai-screen", response_model=ApiResponse[AiScreenResult])
def ai_screen_stocks(query: str = "", db: Session = Depends(get_db)):
    """AI 找股:自然語言條件(如「殖利率 5% 以上的高股息」)→ 已驗證可加入觀察清單的名單。"""
    service = StockService(db)
    result = service.ai_screen(query)
    return ApiResponse(success=True, data=result)

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
        msg = f"今天下跌 {abs(change):.2f}%，主要受板塊震盪影響，非個股營運惡化。先觀察就好，不用焦慮。"
    elif change < 0:
        msg = f"今天小幅調整 {abs(change):.2f}%，屬於正常震盪，不用擔心。"
    else:
        msg = f"今天上漲 {change:.2f}%，走勢強勁，為持股情緒提供良好支撐。"
    return ApiResponse(success=True, data=msg)

@router.get("/{symbol}/ai-analysis", response_model=ApiResponse[str])
def get_stock_ai_analysis(symbol: str, db: Session = Depends(get_db)):
    service = StockService(db)
    stock = service.repo.get_stock(symbol)
    price = service.get_daily_price(symbol)
    
    if not price:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Stock data not found for {symbol}"
        )
        
    name = stock.name if stock else symbol
    close = float(price.close_price)
    change = float(price.change_percent)
    
    from app.services.openai_service import OpenAIService
    from app.services.services import run_async
    
    analysis_text = run_async(
        OpenAIService.fetch_stock_analysis(
            symbol=symbol,
            name=name,
            close_price=close,
            change_percent=change
        )
    )
    
    # Trigger first-time read achievement
    from app.services.services import AchievementService
    ach_service = AchievementService(db)
    ach_service.trigger_unlock("CALM_BEGINNER")
    
    return ApiResponse(success=True, data=analysis_text)
