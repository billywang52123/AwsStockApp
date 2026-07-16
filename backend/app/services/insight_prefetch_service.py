"""/insights 預先計算與快取(消滅分析頁的等待圈圈)。

AgentCore 的多工具個股觀點一次要跑數十秒;這裡在「持股異動 API 完成後」
與「App 啟動 prewarm」時,用背景執行緒先把結果算好存進 insight_cache。
快取鍵 = 持股指紋 + 交易日:使用者再更新庫存、或換日(14:30 換日邏輯,
含模擬日期切換)都會自動失效並重算。

single-flight:同一位使用者同時只跑一次計算(per-user lock),
背景預抓與使用者同步請求撞在一起時,後到者等前者算完直接讀快取,
不會重複打 AgentCore。
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

logger = logging.getLogger(__name__)

# per-user single-flight locks
_locks: dict[str, threading.Lock] = {}
_locks_guard = threading.Lock()


def _user_lock(user_id: str) -> threading.Lock:
    with _locks_guard:
        return _locks.setdefault(user_id, threading.Lock())


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


def build_insights_payload(db: Session, user_id: str) -> dict:
    """與原 /insights 路由相同的計算:規則式為底,AgentCore 成功則覆寫 headline。"""
    from app.core.config import settings
    from app.services.portfolio_analysis_service import StockInsightService

    rule_based = StockInsightService(db).get_insights(user_id)

    if settings.AGENTCORE_STOCK_ANALYSIS_ENABLED:
        try:
            from app.services.agentcore_service import get_agentcore_service

            result = get_agentcore_service().get_stock_insight(user_id)
            if result and result.get("insight_summary"):
                notes_by_symbol = {
                    h["symbol"]: h["note"] for h in result.get("holding_notes", [])
                }
                for item in rule_based["items"]:
                    agent_note = notes_by_symbol.get(item["symbol"])
                    if agent_note:
                        item["headline"] = agent_note
                if rule_based["items"]:
                    rule_based["_agent_insight"] = result["insight_summary"]
                logger.info("Insights enhanced by AgentCore for user %s", user_id)
        except Exception:
            logger.exception("AgentCore insights failed, using rule-based fallback")

    return rule_based


def get_fresh_payload(db: Session, user_id: str) -> dict | None:
    """快取有效(同一天 + 持股沒變)就回 payload,否則 None。"""
    row = db.get(InsightCache, user_id)
    if row is None:
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


def refresh_insights(user_id: str) -> dict:
    """算一次並存快取(single-flight)。可被同步請求或背景執行緒呼叫。"""
    with _user_lock(user_id):
        with SessionLocal() as db:
            # 拿到鎖後再查一次:前一位呼叫者可能已經算好了
            cached = get_fresh_payload(db, user_id)
            if cached is not None:
                return cached

            # 指紋在計算前取:若計算期間持股又變,該次異動會再排一次預抓,
            # 屆時指紋比對不符就會重算,不會卡在舊結果。
            fingerprint = holdings_fingerprint(db, user_id)
            trade_date = effective_trade_date()
            payload = build_insights_payload(db, user_id)

            row = db.get(InsightCache, user_id)
            if row is None:
                row = InsightCache(user_id=user_id)
                db.add(row)
            row.trade_date = trade_date
            row.fingerprint = fingerprint
            row.payload = json.dumps(jsonable_encoder(payload), ensure_ascii=False)
            db.commit()
            return payload


def schedule_insight_prefetch(user_id: str) -> None:
    """背景預抓:立即返回,不擋住呼叫端的回應。"""

    def _run() -> None:
        try:
            refresh_insights(user_id)
            logger.info("Insight prefetch done for %s", user_id)
        except Exception:
            logger.exception("Insight prefetch failed for %s", user_id)

    threading.Thread(target=_run, daemon=True, name="insight-prefetch").start()
