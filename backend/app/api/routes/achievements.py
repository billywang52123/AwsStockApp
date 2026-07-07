from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session
from app.core.auth import get_current_user_id
from app.db.database import get_db
from app.schemas.common_schema import ApiResponse
from app.services.services import AchievementService

router = APIRouter(prefix="/achievements", tags=["Achievements"])

@router.get("", response_model=ApiResponse[list])
def get_achievements(db: Session = Depends(get_db), user_id: str = Depends(get_current_user_id)):
    service = AchievementService(db)
    data = service.get_achievements(user_id)
    return ApiResponse(success=True, data=data)
