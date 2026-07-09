from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from app.core.auth import get_current_user_id
from app.db.database import get_db
from app.schemas.common_schema import ApiResponse
from app.schemas.analysis_schema import (
    PortfolioAnalysisRead, InsightListRead, StockInsightDetail
)
from app.services.portfolio_analysis_service import PortfolioAnalysisService, StockInsightService

router = APIRouter(tags=["Analysis"])


@router.get("/portfolio/analysis", response_model=ApiResponse[PortfolioAnalysisRead])
def get_portfolio_analysis(db: Session = Depends(get_db), user_id: str = Depends(get_current_user_id)):
    """庫存分析總覽(8a/8b/8c):總市值、風險/焦慮分數、產業曝險、持股明細、風險提醒。"""
    service = PortfolioAnalysisService(db)
    return ApiResponse(success=True, data=service.get_analysis(user_id))


@router.get("/insights", response_model=ApiResponse[InsightListRead])
def get_stock_insights(db: Session = Depends(get_db), user_id: str = Depends(get_current_user_id)):
    """個股 AI 觀點總覽(8d):每檔持股的觀點、分數與一句話理由。"""
    service = StockInsightService(db)
    return ApiResponse(success=True, data=service.get_insights(user_id))


@router.get("/insights/{symbol}", response_model=ApiResponse[StockInsightDetail])
def get_stock_insight_detail(symbol: str, db: Session = Depends(get_db), user_id: str = Depends(get_current_user_id)):
    """個股觀點詳情(8e/11f):多空溫度計分數、訊號與白話總結;
    持股與觀察股都可查,查無此股才 404。"""
    service = StockInsightService(db)
    detail = service.get_insight_detail(symbol, user_id)
    if detail is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Stock not found"
        )
    return ApiResponse(success=True, data=detail)
