"""/insights 預先計算與快取(消滅分析頁的等待圈圈)。

慢的計算(Claude 走 AgentCore 多工具、OpenAI 走本地編排 + Chat Completions)
在「持股異動 API 完成後」與「App 啟動 prewarm」時,用背景執行緒先算好
存進 insight_cache。快取鍵 = 持股指紋 + 交易日 + AI 引擎(provider):
再更新庫存、換日(14:30 換日邏輯,含模擬日期切換)、或在設定頁切換
AI 引擎,都會自動失效並重算。

single-flight:同一位使用者+同一引擎同時只跑一次計算(per-key lock),
背景預抓與使用者同步請求撞在一起時,後到者等前者算完直接讀快取,
不會重複打 AgentCore / OpenAI。

AI 增強失敗(AgentCore 掛掉、OpenAI 回 fallback)時照樣回應規則式結果,
但「不寫入快取」,下一次請求/預抓會自動重試,不會把失敗結果鎖一整天。
"""

from __future__ import annotations

import hashlib
import json
import logging
import threading

from fastapi.encoders import jsonable_encoder
from sqlalchemy import and_, select
from sqlalchemy.orm import Session

from app.db.database import SessionLocal
from app.models.insight_cache import InsightCache
from app.models.portfolio import PortfolioItem
from app.services.cmoney_service import effective_trade_date
from app.services.llm_router import (
    PROVIDER_OPENAI,
    current_provider,
    reset_provider,
    set_provider_from_header,
)

logger = logging.getLogger(__name__)

# per-(user, provider) single-flight locks
_locks: dict[str, threading.Lock] = {}
_locks_guard = threading.Lock()


def _flight_lock(user_id: str, provider: str) -> threading.Lock:
    with _locks_guard:
        return _locks.setdefault(f"{user_id}:{provider}", threading.Lock())


def holdings_fingerprint(db: Session, user_id: str) -> str:
    """目前有效持股(未 exited 的 lots)的內容指紋。"""
    stmt = select(PortfolioItem).where(
        and_(
            PortfolioItem.user_id == user_id,
            (PortfolioItem.status.is_(None)) | (PortfolioItem.status != "exited"),
        )
    )
    parts = sorted(
        f"{l.symbol}|{l.shares or 0}|{l.cost_price if l.cost_price is not None else ''}|{l.broker or ''}"
        for l in db.scalars(stmt).all()
    )
    return hashlib.sha256(";".join(parts).encode("utf-8")).hexdigest()


def build_insights_payload(db: Session, user_id: str, provider: str) -> tuple[dict, bool]:
    """規則式為底;依 provider 走 AgentCore(claude)或本地編排(openai)
    產生 AI 觀點覆寫 headline。回傳 (payload, ai_enriched)。

    ai_enriched=False 表示 AI 增強失敗、payload 是純規則式 —
    呼叫端可據此決定不要快取,讓下一次自動重試。
    """
    from app.core.config import settings
    from app.services.portfolio_analysis_service import StockInsightService

    rule_based = StockInsightService(db).get_insights(user_id)
    if not rule_based["items"]:
        # 沒有持股就沒東西可增強,視為完整結果(可快取,避免空投組反覆打 AI)
        return rule_based, True

    ai_result = None
    if provider == PROVIDER_OPENAI:
        try:
            from app.services import local_insight_service
            result = local_insight_service.generate_local_insight(db, user_id)
            # generate_local_insight 失敗時回傳模組常數 FALLBACK(也帶
            # insight_summary),那是安撫文案不是分析,不能當增強結果快取
            if result is not local_insight_service.FALLBACK:
                ai_result = result
        except Exception:
            logger.exception("Local OpenAI insights failed for %s; rule-based only", user_id)
    elif settings.AGENTCORE_STOCK_ANALYSIS_ENABLED:
        try:
            from app.services.agentcore_service import get_agentcore_service
            ai_result = get_agentcore_service().get_stock_insight(user_id)
        except Exception:
            logger.exception("AgentCore insights failed for %s; rule-based only", user_id)

    if not (ai_result and ai_result.get("insight_summary")):
        return rule_based, False

    notes_by_symbol = {h["symbol"]: h["note"] for h in ai_result.get("holding_notes", [])}
    for item in rule_based["items"]:
        agent_note = notes_by_symbol.get(item["symbol"])
        if agent_note:
            item["headline"] = agent_note
    rule_based["_agent_insight"] = ai_result["insight_summary"]
    logger.info("Insights enriched via %s for user %s", provider, user_id)
    return rule_based, True


def get_fresh_payload(db: Session, user_id: str, provider: str) -> dict | None:
    """快取有效(同一天 + 持股沒變 + 同一引擎)就回 payload,否則 None。"""
    row = db.get(InsightCache, user_id)
    if row is None:
        return None
    if (row.provider or "claude") != provider:
        return None
    if row.trade_date != effective_trade_date():
        return None
    if row.fingerprint != holdings_fingerprint(db, user_id):
        return None
    try:
        return json.loads(row.payload)
    except Exception:
        logger.warning("Corrupt insight cache for %s; recomputing", user_id)
        return None


def refresh_insights(user_id: str, provider: str) -> dict:
    """算一次並存快取(single-flight)。可被同步請求或背景執行緒呼叫。

    背景執行緒沒有 request contextvar,這裡把 provider 綁回當前 context,
    讓 local_insight_service 內部的 get_llm() 解析到正確引擎。
    """
    with _flight_lock(user_id, provider):
        token = set_provider_from_header(provider)
        try:
            with SessionLocal() as db:
                # 拿到鎖後再查一次:前一位呼叫者可能已經算好了
                cached = get_fresh_payload(db, user_id, provider)
                if cached is not None:
                    return cached

                # 指紋在計算前取:若計算期間持股又變,該次異動會再排一次預抓,
                # 屆時指紋比對不符就會重算,不會卡在舊結果。
                fingerprint = holdings_fingerprint(db, user_id)
                trade_date = effective_trade_date()
                payload, ai_enriched = build_insights_payload(db, user_id, provider)

                if not ai_enriched:
                    # AI 失敗:回應照給,但不快取,下一次自動重試
                    return payload

                row = db.get(InsightCache, user_id)
                if row is None:
                    row = InsightCache(user_id=user_id)
                    db.add(row)
                row.trade_date = trade_date
                row.fingerprint = fingerprint
                row.provider = provider
                row.payload = json.dumps(jsonable_encoder(payload), ensure_ascii=False)
                db.commit()
                return payload
        finally:
            reset_provider(token)


def schedule_insight_prefetch(user_id: str, provider: str | None = None) -> None:
    """背景預抓:立即返回,不擋住呼叫端的回應。

    provider 預設取呼叫端 request 的 X-AI-Provider(必須在 request context
    內取,新 thread 讀不到 contextvar),再顯式帶進背景執行緒。
    """
    resolved = provider or current_provider()

    def _run() -> None:
        try:
            refresh_insights(user_id, resolved)
            logger.info("Insight prefetch done for %s via %s", user_id, resolved)
        except Exception:
            logger.exception("Insight prefetch failed for %s", user_id)

    threading.Thread(target=_run, daemon=True, name="insight-prefetch").start()
