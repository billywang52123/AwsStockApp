from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session
from app.db.database import get_db
from app.schemas.common_schema import ApiResponse
from app.schemas.market_schema import MarketCompareResultRead
from app.services.services import MarketCompareService

router = APIRouter(prefix="/market", tags=["Market"])

@router.get("/compare", response_model=ApiResponse[MarketCompareResultRead])
def get_market_compare(db: Session = Depends(get_db)):
    service = MarketCompareService(db)
    compare = service.compare_market()
    return ApiResponse(success=True, data=compare)
