"""每日抽卡包 + AI 信任系統 API(spec 06 · 15a–15k,取代御神籤)。"""

from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.core.auth import get_current_user_id
from app.db.database import get_db
from app.schemas.common_schema import ApiResponse
from app.schemas.pack_schema import DailyPackRead, PackShelfRead, WeeklyCheckupRead
from app.services.daily_pack_service import DailyPackService

router = APIRouter(prefix="/pack", tags=["DailyPack"])


@router.get("/today", response_model=ApiResponse[DailyPackRead])
def get_today_pack(force: bool = False, db: Session = Depends(get_db),
                   user_id: str = Depends(get_current_user_id)):
    """今日卡包(15a):第一次請求時產生並存檔,全天回同一包。

    force=true(重生測試用):丟棄今日包,依當下持股與市場重算。"""
    service = DailyPackService(db)
    pack = service.get_today(user_id, force=force)
    db.commit()
    return ApiResponse(success=True, data=pack)


@router.post("/open", response_model=ApiResponse[bool])
def open_pack(db: Session = Depends(get_db), user_id: str = Depends(get_current_user_id)):
    """開包動畫看完(或跳過)後標記,之後開頁直達完成態(15e)。"""
    service = DailyPackService(db)
    ok = service.mark_opened(user_id)
    db.commit()
    return ApiResponse(success=True, data=ok)


@router.get("/shelf", response_model=ApiResponse[PackShelfRead])
def get_pack_shelf(db: Session = Depends(get_db), user_id: str = Depends(get_current_user_id)):
    """卡包架(15j):每檔持股一包 + 歷史卡片圖鑑。"""
    service = DailyPackService(db)
    shelf = service.get_shelf(user_id)
    db.commit()   # CMoney 模擬日同步(冪等)可能寫入 public 表
    return ApiResponse(success=True, data=shelf)


@router.get("/weekly-checkup", response_model=ApiResponse[WeeklyCheckupRead])
def get_weekly_checkup(db: Session = Depends(get_db), user_id: str = Depends(get_current_user_id)):
    """週末體檢(15k):AI 本週誠實度對帳,說中沒說中都照實呈現。"""
    service = DailyPackService(db)
    checkup = service.get_weekly_checkup(user_id)
    db.commit()   # CMoney 模擬日同步(冪等)可能寫入 public 表
    return ApiResponse(success=True, data=checkup)
