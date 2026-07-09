"""每日御神籤 API — spec 第十輪 12a–12d(每日抽卡 → 日式搖籤)。"""

from typing import Optional

from fastapi import APIRouter, Depends, status
from sqlalchemy.orm import Session

from app.core.auth import get_current_user_id
from app.db.database import get_db
from app.schemas.common_schema import ApiResponse
from app.schemas.fortune_schema import FortuneRead
from app.services.fortune_service import FortuneService

router = APIRouter(prefix="/fortune", tags=["Fortune"])


@router.post("/draw", response_model=ApiResponse[FortuneRead], status_code=status.HTTP_201_CREATED)
def draw_fortune(db: Session = Depends(get_db), user_id: str = Depends(get_current_user_id)):
    """搖籤(12b):每天一支;當天再抽直接回同一支籤。"""
    service = FortuneService(db)
    fortune = service.draw(user_id)
    db.commit()
    return ApiResponse(success=True, data=fortune)


@router.get("/today", response_model=ApiResponse[Optional[FortuneRead]])
def get_today_fortune(db: Session = Depends(get_db), user_id: str = Depends(get_current_user_id)):
    """今日籤詩(12c):尚未抽過回 null,前端顯示 12a 搖籤入口。"""
    service = FortuneService(db)
    return ApiResponse(success=True, data=service.get_today(user_id))
