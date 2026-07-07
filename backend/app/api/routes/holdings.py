"""持股(券商分帳聚合)與異動 API — spec 04 · 9a–9e."""

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app.core.auth import get_current_user_id
from app.db.database import get_db
from app.schemas.common_schema import ApiResponse
from app.schemas.holding_schema import (
    HoldingRead, HoldingActivityRead, TradeRequest, OverrideRequest,
    TradeResult, ImportMergeRequest, ImportMergeResult,
)
from app.services.holding_service import HoldingService

router = APIRouter(prefix="/portfolio", tags=["Holdings"])


def _service(db: Session) -> HoldingService:
    return HoldingService(db)


@router.get("/holdings", response_model=ApiResponse[list[HoldingRead]])
def list_holdings(db: Session = Depends(get_db), user_id: str = Depends(get_current_user_id)):
    return ApiResponse(success=True, data=_service(db).get_holdings(user_id))


@router.get("/holdings/{symbol}", response_model=ApiResponse[HoldingRead])
def get_holding(symbol: str, db: Session = Depends(get_db), user_id: str = Depends(get_current_user_id)):
    holding = _service(db).get_holding(user_id, symbol)
    if holding is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="找不到這檔持股")
    return ApiResponse(success=True, data=holding)


def _run_trade(db: Session, fn, *args) -> TradeResult:
    try:
        result = fn(*args)
    except ValueError as e:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(e))
    except LookupError as e:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(e))
    db.commit()
    return result


@router.post("/holdings/{symbol}/buy", response_model=ApiResponse[TradeResult])
def buy(symbol: str, body: TradeRequest, db: Session = Depends(get_db),
        user_id: str = Depends(get_current_user_id)):
    service = _service(db)
    result = _run_trade(db, service.buy, user_id, symbol, body.shares, body.price, body.broker)
    return ApiResponse(success=True, data=result)


@router.post("/holdings/{symbol}/sell", response_model=ApiResponse[TradeResult])
def sell(symbol: str, body: TradeRequest, db: Session = Depends(get_db),
         user_id: str = Depends(get_current_user_id)):
    service = _service(db)
    result = _run_trade(db, service.sell, user_id, symbol, body.shares, body.price, body.broker)
    return ApiResponse(success=True, data=result)


@router.post("/holdings/{symbol}/override", response_model=ApiResponse[TradeResult])
def override(symbol: str, body: OverrideRequest, db: Session = Depends(get_db),
             user_id: str = Depends(get_current_user_id)):
    service = _service(db)
    result = _run_trade(db, service.override, user_id, symbol, body.shares, body.broker)
    return ApiResponse(success=True, data=result)


@router.post("/holdings/{symbol}/restore", response_model=ApiResponse[TradeResult])
def restore(symbol: str, db: Session = Depends(get_db),
            user_id: str = Depends(get_current_user_id)):
    service = _service(db)
    result = _run_trade(db, service.restore, user_id, symbol)
    return ApiResponse(success=True, data=result)


@router.post("/import/merge", response_model=ApiResponse[ImportMergeResult])
def import_merge(body: ImportMergeRequest, db: Session = Depends(get_db),
                 user_id: str = Depends(get_current_user_id)):
    service = _service(db)
    result = service.import_merge(user_id, [d.model_dump() for d in body.decisions])
    db.commit()
    return ApiResponse(success=True, data=result)


@router.get("/holdings/{symbol}/activities", response_model=ApiResponse[list[HoldingActivityRead]])
def list_activities(symbol: str, db: Session = Depends(get_db),
                    user_id: str = Depends(get_current_user_id)):
    return ApiResponse(success=True, data=_service(db).get_activities(user_id, symbol))


@router.delete("/activities/{activity_id}", response_model=ApiResponse[bool])
def delete_activity(activity_id: str, db: Session = Depends(get_db),
                    user_id: str = Depends(get_current_user_id)):
    ok = _service(db).delete_activity(user_id, activity_id)
    if not ok:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="找不到這筆異動")
    db.commit()
    return ApiResponse(success=True, data=True)
