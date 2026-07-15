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
    啟用 AgentCore 時,agent 會呼叫多工具(法人/社群/動能)產生更豐富的觀點;
    失敗時退回規則式計算。"""
    from app.core.config import settings

    if settings.AGENTCORE_STOCK_ANALYSIS_ENABLED:
        from starlette.concurrency import run_in_threadpool
        from app.services.agentcore_service import get_agentcore_service
        from app.services.services import run_async
        import logging
        logger = logging.getLogger(__name__)
        try:
            agentcore = get_agentcore_service()
            result = run_async(run_in_threadpool(agentcore.get_stock_insight, user_id))
            if result and result.get("insight_summary"):
                # Map AgentCore holding_notes → InsightListRead format
                holding_notes = result.get("holding_notes", [])
                # We need holdings data to fill weight_percent, industry etc.
                service = StockInsightService(db)
                rule_based = service.get_insights(user_id)
                # Enhance rule-based items with AgentCore notes
                notes_by_symbol = {h["symbol"]: h["note"] for h in holding_notes}
                for item in rule_based["items"]:
                    agent_note = notes_by_symbol.get(item["symbol"])
                    if agent_note:
                        item["headline"] = agent_note
                # Prepend overall insight as headline of first item if available
                if rule_based["items"] and result.get("insight_summary"):
                    rule_based["_agent_insight"] = result["insight_summary"]
                logger.info("Insights enhanced by AgentCore for user %s", user_id)
                return ApiResponse(success=True, data=rule_based)
        except Exception:
            logger.exception("AgentCore insights failed, using rule-based fallback")

    # Fallback: pure rule-based
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
