from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session
from app.core.auth import get_current_user_id
from app.db.database import get_db
from app.schemas.common_schema import ApiResponse
from app.schemas.market_schema import MarketCompareResultRead
from app.services.services import MarketCompareService

router = APIRouter(prefix="/market", tags=["Market"])

@router.get("/compare", response_model=ApiResponse[MarketCompareResultRead])
def get_market_compare(db: Session = Depends(get_db), user_id: str = Depends(get_current_user_id)):
    service = MarketCompareService(db)
    compare = service.compare_market(user_id)
    return ApiResponse(success=True, data=compare)
