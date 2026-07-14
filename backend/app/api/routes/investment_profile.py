"""投資風格問卷、目前風格、習慣歷史與 prompt context API。"""

from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from app.core.auth import get_current_user_id
from app.db.database import get_db
from app.schemas.common_schema import ApiResponse
from app.schemas.investment_profile_schema import (
    HabitSnapshotRead,
    InvestmentProfileRead,
    PromptContextRead,
    QuestionnaireAnswers,
    QuestionnaireRead,
)
from app.services.investment_profile_service import InvestmentProfileService


router = APIRouter(prefix="/investment-profile", tags=["InvestmentProfile"])


def _service(db: Session) -> InvestmentProfileService:
    return InvestmentProfileService(db)


@router.get("/questionnaire", response_model=ApiResponse[QuestionnaireRead])
def get_questionnaire(db: Session = Depends(get_db),
                      user_id: str = Depends(get_current_user_id)):
    return ApiResponse(success=True, data=_service(db).get_questionnaire(user_id))


@router.put("/questionnaire", response_model=ApiResponse[InvestmentProfileRead])
def save_questionnaire(body: QuestionnaireAnswers, db: Session = Depends(get_db),
                       user_id: str = Depends(get_current_user_id)):
    result = _service(db).submit_questionnaire(user_id, body.model_dump())
    db.commit()
    return ApiResponse(success=True, data=result)


@router.get("", response_model=ApiResponse[InvestmentProfileRead])
def get_profile(db: Session = Depends(get_db),
                user_id: str = Depends(get_current_user_id)):
    return ApiResponse(success=True, data=_service(db).get_profile(user_id))


@router.get("/history", response_model=ApiResponse[list[HabitSnapshotRead]])
def get_history(limit: int = Query(default=30, ge=1, le=100),
                db: Session = Depends(get_db),
                user_id: str = Depends(get_current_user_id)):
    return ApiResponse(success=True, data=_service(db).history(user_id, limit))


@router.post("/refresh", response_model=ApiResponse[HabitSnapshotRead])
def refresh_profile(db: Session = Depends(get_db),
                    user_id: str = Depends(get_current_user_id)):
    """前端可手動要求重算；正常買賣/匯入後後端會自動建立快照。"""
    result = _service(db).capture_habit_snapshot(user_id, "manual_refresh")
    db.commit()
    return ApiResponse(success=True, data=result)


@router.get("/prompt-context", response_model=ApiResponse[PromptContextRead])
def get_prompt_context(db: Session = Depends(get_db),
                       user_id: str = Depends(get_current_user_id)):
    return ApiResponse(success=True, data=_service(db).prompt_context(user_id))
