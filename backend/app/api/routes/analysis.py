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
    """個股 AI 觀點總覽(8d):每檔持股的觀點、分數與一句話理由。

    依 X-AI-Provider 選路:claude 走 AgentCore 多工具、openai 走本地編排
    (local_insight_service,單發 Chat Completions,較快)。兩條路都吃同一套
    insight_cache(鍵含 provider):持股異動後、App 啟動 prewarm 時已背景算好,
    命中直接秒回;未命中才同步計算(single-flight,不會重複打 AI)。"""
    from app.services.insight_prefetch_service import get_fresh_payload, refresh_insights
    from app.services.llm_router import current_provider

    provider = current_provider()
    cached = get_fresh_payload(db, user_id, provider)
    if cached is not None:
        return ApiResponse(success=True, data=cached)
    return ApiResponse(success=True, data=refresh_insights(user_id, provider))


@router.post("/insights/prewarm", response_model=ApiResponse[str])
def prewarm_insights(db: Session = Depends(get_db), user_id: str = Depends(get_current_user_id)):
    """App 啟動時呼叫:排背景預抓(insights 總覽 + 每檔持股的個股白話分析,
    各環節新鮮就自動跳過,不會重複打 AI)。insights 已新鮮回 ready,否則 warming。"""
    from app.services.insight_prefetch_service import get_fresh_payload, schedule_insight_prefetch
    from app.services.llm_router import current_provider

    provider = current_provider()
    ready = get_fresh_payload(db, user_id, provider) is not None
    schedule_insight_prefetch(user_id, provider)
    return ApiResponse(success=True, data="ready" if ready else "warming")


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
