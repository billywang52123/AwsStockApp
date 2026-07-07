from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session
from app.db.database import get_db
from app.schemas.common_schema import ApiResponse
from app.services.services import AchievementService

router = APIRouter(prefix="/achievements", tags=["Achievements"])

@router.get("", response_model=ApiResponse[list])
def get_achievements(db: Session = Depends(get_db)):
    service = AchievementService(db)
    data = service.get_achievements()
    return ApiResponse(success=True, data=data)
