from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session
from app.db.database import get_db
from app.schemas.common_schema import ApiResponse
from app.schemas.anxiety_schema import AnxietyResultRead
from app.services.services import AnxietyScoreService

router = APIRouter(prefix="/anxiety", tags=["Anxiety"])

@router.get("/today", response_model=ApiResponse[AnxietyResultRead])
def get_today_anxiety(db: Session = Depends(get_db)):
    service = AnxietyScoreService(db)
    result = service.calculate_anxiety()
    return ApiResponse(success=True, data=result)
