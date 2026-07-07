"""隱私儀表板 API(spec 05 · 10a).

原則:
- summary 回傳「我們實際持有的資料」逐類筆數,App 端即時顯示。
- delete-all 當下同步刪除,回傳各類刪除筆數 —— 刪除要真的即時、可見,
  不是「已收到您的請求」。
- 後端沒有用戶資料表:登入只換一組匿名編號,Email 不入庫。
"""

from fastapi import APIRouter, Depends
from pydantic import BaseModel
from sqlalchemy import delete, func, select
from sqlalchemy.orm import Session

from app.core.auth import get_current_user_id
from app.db.database import get_db
from app.models.achievement import AchievementModel
from app.models.card_result import CardResultModel
from app.models.holding_activity import HoldingActivityModel
from app.models.portfolio import PortfolioItem
from app.models.reminder import ReminderSettingModel
from app.schemas.common_schema import ApiResponse

router = APIRouter(prefix="/privacy", tags=["Privacy"])

# (回傳欄位, model) —— 我們持有的全部用戶資料就這五類
_USER_TABLES = [
    ("holdings", PortfolioItem),
    ("activities", HoldingActivityModel),
    ("card_results", CardResultModel),
    ("achievements", AchievementModel),
    ("reminder_settings", ReminderSettingModel),
]


class PrivacySummary(BaseModel):
    holdings: int
    activities: int
    card_results: int
    achievements: int
    reminder_settings: int


class DeleteAllResult(BaseModel):
    deleted: PrivacySummary


@router.get("/summary", response_model=ApiResponse[PrivacySummary])
def privacy_summary(db: Session = Depends(get_db), user_id: str = Depends(get_current_user_id)):
    counts = {
        key: db.scalar(select(func.count()).where(model.user_id == user_id)) or 0
        for key, model in _USER_TABLES
    }
    return ApiResponse(success=True, data=PrivacySummary(**counts))


@router.delete("/all", response_model=ApiResponse[DeleteAllResult])
def delete_all_user_data(db: Session = Depends(get_db), user_id: str = Depends(get_current_user_id)):
    """一鍵全部刪除:同步刪光這個匿名編號名下的所有資料."""
    deleted = {}
    for key, model in _USER_TABLES:
        result = db.execute(delete(model).where(model.user_id == user_id))
        deleted[key] = result.rowcount or 0
    db.commit()
    return ApiResponse(success=True, data=DeleteAllResult(deleted=PrivacySummary(**deleted)))
