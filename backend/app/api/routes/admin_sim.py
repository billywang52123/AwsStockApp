"""模擬時鐘 API — 展示/開發用,調整全 App 的「今天」以切換模擬交易日。

CMoney 是 2025 模擬資料,交易日 = 今天 − 1 年。設定這裡的「模擬今天」後,
每日卡包、個股價、大盤、庫存分析都會一起移動到對應的模擬日。

安全備註:此端點會改動全域狀態(所有使用者共用同一個模擬今天),
定位是展示工具。若要在正式環境鎖起來,可在 router 加上
dependencies=[Depends(verify_admin_key)] 並提供 ADMIN_API_KEY。
"""
from fastapi import APIRouter, Depends, Header
from sqlalchemy.orm import Session

from app.db.database import get_db
from app.schemas.common_schema import ApiResponse
from app.schemas.sim_date_schema import SimDateStatus, SimDateUpdate
from app.services import sim_clock
from app.services.cmoney_service import (
    CMoneyDataService, effective_trade_date, simulated_target,
)

router = APIRouter(prefix="/admin/sim-date", tags=["Admin · Sim Clock"])


def _status(db: Session) -> SimDateStatus:
    today = effective_trade_date()
    sim_target = simulated_target(today)
    cm = CMoneyDataService(db)
    available = cm.available
    resolved = None
    if available:
        yyyymmdd = cm.resolve_trade_date(sim_target)
        resolved = cm.to_date(yyyymmdd) if yyyymmdd else None
    return SimDateStatus(
        overridden=sim_clock.get_override() is not None,
        effective_today=today,
        simulated_trade_date=sim_target,
        resolved_data_date=resolved,
        data_available=available,
    )


@router.get("", response_model=ApiResponse[SimDateStatus])
def get_sim_date(db: Session = Depends(get_db)):
    """目前的模擬今天、對應模擬交易日,以及 CMoney 實際回退到的資料日。"""
    return ApiResponse(success=True, data=_status(db))


@router.put("", response_model=ApiResponse[SimDateStatus])
def set_sim_date(payload: SimDateUpdate, db: Session = Depends(get_db),
                 x_user_id: str | None = Header(default=None)):
    """設定模擬今天(持久化,重啟後仍生效)。整個 App 立刻切到對應模擬日。"""
    sim_clock.set_override(db, payload.date)
    # 換日後 insight 快取必失效,替操作者先預熱,分析頁才不用等
    if x_user_id:
        from app.services.insight_prefetch_service import schedule_insight_prefetch
        schedule_insight_prefetch(x_user_id)
    return ApiResponse(
        success=True, data=_status(db),
        message=f"模擬今天已設為 {payload.date.isoformat()}",
    )


@router.delete("", response_model=ApiResponse[SimDateStatus])
def clear_sim_date(db: Session = Depends(get_db),
                   x_user_id: str | None = Header(default=None)):
    """清除覆寫,恢復用真實系統時間。"""
    sim_clock.clear_override(db)
    if x_user_id:
        from app.services.insight_prefetch_service import schedule_insight_prefetch
        schedule_insight_prefetch(x_user_id)
    return ApiResponse(
        success=True, data=_status(db),
        message="已恢復真實時間",
    )
