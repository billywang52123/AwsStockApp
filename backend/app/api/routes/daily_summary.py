from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session
from app.db.database import get_db
from app.schemas.common_schema import ApiResponse
from app.schemas.summary_schema import DailySummaryRead
from app.services.services import DailySummaryService

router = APIRouter(prefix="/daily-summary", tags=["Daily Summary"])

@router.get("", response_model=ApiResponse[DailySummaryRead])
def get_daily_summary(db: Session = Depends(get_db)):
    service = DailySummaryService(db)
    summary = service.get_summary()
    return ApiResponse(success=True, data=summary)
