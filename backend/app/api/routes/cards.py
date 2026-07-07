from fastapi import APIRouter, Depends, status
from sqlalchemy.orm import Session
from app.core.auth import get_current_user_id
from app.db.database import get_db
from app.schemas.common_schema import ApiResponse
from app.schemas.card_schema import DrawCardResultRead
from app.services.services import CardDrawService
from typing import Optional

router = APIRouter(prefix="/cards", tags=["Cards"])

@router.post("/draw", response_model=ApiResponse[DrawCardResultRead], status_code=status.HTTP_201_CREATED)
def draw_today_card(db: Session = Depends(get_db), user_id: str = Depends(get_current_user_id)):
    service = CardDrawService(db)
    card = service.draw_today_card(user_id)
    db.commit()
    return ApiResponse(success=True, data=card)

@router.get("/today", response_model=ApiResponse[Optional[DrawCardResultRead]])
def get_today_card(db: Session = Depends(get_db), user_id: str = Depends(get_current_user_id)):
    service = CardDrawService(db)
    card = service.get_today_card(user_id)
    return ApiResponse(success=True, data=card)
