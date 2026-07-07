from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session
from app.core.auth import get_current_user_id
from app.db.database import get_db
from app.schemas.common_schema import ApiResponse
from app.schemas.reminder_schema import ReminderSettingRead
from app.services.services import ReminderService

router = APIRouter(prefix="/reminder-setting", tags=["Reminders"])

@router.get("", response_model=ApiResponse[ReminderSettingRead])
def get_reminder_setting(db: Session = Depends(get_db), user_id: str = Depends(get_current_user_id)):
    service = ReminderService(db)
    settings = service.get_settings(user_id)
    return ApiResponse(success=True, data=settings)

@router.put("", response_model=ApiResponse[ReminderSettingRead])
def update_reminder_setting(settings_data: ReminderSettingRead, db: Session = Depends(get_db), user_id: str = Depends(get_current_user_id)):
    service = ReminderService(db)
    updated = service.save_settings(settings_data.model_dump(), user_id)
    db.commit()
    return ApiResponse(success=True, data=updated)
