from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session
from app.db.database import get_db
from app.schemas.common_schema import ApiResponse
from app.schemas.stock_schema import StockRead
from app.services.services import StockService

router = APIRouter(prefix="/recommendations", tags=["Recommendations"])

@router.get("/stocks", response_model=ApiResponse[list[StockRead]])
def get_recommendations(symbol: str = Query(..., description="The symbol to base recommendations on"), db: Session = Depends(get_db)):
    service = StockService(db)
    recs = service.get_recommendations(symbol)
    return ApiResponse(success=True, data=recs)
