"""觀察清單 API — spec 05 · 11a–11f。"""

from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.orm import Session

from app.core.auth import get_current_user_id
from app.db.database import get_db
from app.schemas.common_schema import ApiResponse
from app.schemas.watchlist_schema import (
    WatchlistCreate, WatchlistSummary, WatchlistIndexRead, WatchlistDetailRead,
    WatchItemAdd, WatchStockRead, ConvertRequest, ConvertResult,
    WatchlistAnalysisRead, WatchInsightListRead,
)
from app.services.watchlist_service import WatchlistService

router = APIRouter(prefix="/watchlists", tags=["Watchlists"])


def _service(db: Session) -> WatchlistService:
    return WatchlistService(db)


@router.get("", response_model=ApiResponse[WatchlistIndexRead])
def list_watchlists(db: Session = Depends(get_db), user_id: str = Depends(get_current_user_id)):
    """11a 清單切換選單:持股檔數 + 各觀察清單(名稱/顏色/檔數)。"""
    return ApiResponse(success=True, data=_service(db).get_index(user_id))


@router.post("", response_model=ApiResponse[WatchlistSummary])
def create_watchlist(body: WatchlistCreate, db: Session = Depends(get_db),
                     user_id: str = Depends(get_current_user_id)):
    """11b 新增觀察清單。"""
    try:
        result = _service(db).create(user_id, body.name, body.color)
    except ValueError as e:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(e))
    db.commit()
    return ApiResponse(success=True, data=result)


# 注意:靜態路徑(analysis / insights)必須排在 /{watchlist_id} 之前

@router.get("/analysis", response_model=ApiResponse[WatchlistAnalysisRead])
def watchlist_analysis(watchlist_id: Optional[str] = Query(None),
                       db: Session = Depends(get_db),
                       user_id: str = Depends(get_current_user_id)):
    """11e 觀察清單分析:平均評分、產業分布、與庫存重疊提醒。不帶 watchlist_id 表示全部。"""
    return ApiResponse(success=True, data=_service(db).get_analysis(user_id, watchlist_id))


@router.get("/insights", response_model=ApiResponse[WatchInsightListRead])
def watchlist_insights(db: Session = Depends(get_db),
                       user_id: str = Depends(get_current_user_id)):
    """11f 個股觀點「觀察清單」分頁:全部觀察股的評分與一句話理由。"""
    return ApiResponse(success=True, data=_service(db).get_insights(user_id))


@router.get("/{watchlist_id}", response_model=ApiResponse[WatchlistDetailRead])
def get_watchlist(watchlist_id: str, db: Session = Depends(get_db),
                  user_id: str = Depends(get_current_user_id)):
    """11c 觀察清單頁:平均分數卡 + 觀察股列。"""
    detail = _service(db).get_detail(user_id, watchlist_id)
    if detail is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="找不到這份觀察清單")
    return ApiResponse(success=True, data=detail)


@router.delete("/{watchlist_id}", response_model=ApiResponse[bool])
def delete_watchlist(watchlist_id: str, db: Session = Depends(get_db),
                     user_id: str = Depends(get_current_user_id)):
    if not _service(db).delete(user_id, watchlist_id):
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="找不到這份觀察清單")
    db.commit()
    return ApiResponse(success=True, data=True)


@router.post("/{watchlist_id}/items", response_model=ApiResponse[WatchStockRead])
def add_item(watchlist_id: str, body: WatchItemAdd, db: Session = Depends(get_db),
             user_id: str = Depends(get_current_user_id)):
    try:
        result = _service(db).add_item(user_id, watchlist_id, body.symbol)
    except LookupError as e:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(e))
    db.commit()
    return ApiResponse(success=True, data=result)


@router.delete("/{watchlist_id}/items/{symbol}", response_model=ApiResponse[bool])
def remove_item(watchlist_id: str, symbol: str, db: Session = Depends(get_db),
                user_id: str = Depends(get_current_user_id)):
    if not _service(db).remove_item(user_id, watchlist_id, symbol):
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="這檔股票不在這份觀察清單裡")
    db.commit()
    return ApiResponse(success=True, data=True)


@router.post("/{watchlist_id}/items/{symbol}/convert", response_model=ApiResponse[ConvertResult])
def convert_to_holding(watchlist_id: str, symbol: str, body: ConvertRequest,
                       db: Session = Depends(get_db),
                       user_id: str = Depends(get_current_user_id)):
    """11d 轉入庫存:建立持股後移出觀察清單,開始計入市值/損益/焦慮分數。"""
    try:
        result = _service(db).convert_to_holding(user_id, watchlist_id, symbol,
                                                 body.shares, body.price)
    except LookupError as e:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(e))
    except ValueError as e:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(e))
    db.commit()
    return ApiResponse(success=True, data=result)
