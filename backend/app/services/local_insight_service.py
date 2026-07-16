"""Local portfolio insight generation (bypasses AgentCore).

When X-AI-Provider: openai, instead of invoking AgentCore Runtime (which is
locked to Bedrock model), we gather the same data from internal APIs directly
and call the selected LLM (OpenAI or Bedrock) in a single shot.

This is faster than AgentCore because:
- No multi-turn agent reasoning overhead
- No Lambda cold starts per tool
- Single LLM call with all data pre-gathered

The output format matches AgentCore's response exactly:
{"insight_summary": "...", "plain_talk": "...", "holding_notes": [...]}
"""

from __future__ import annotations

import json
import logging
from typing import Any

from starlette.concurrency import run_in_threadpool
from sqlalchemy.orm import Session

from app.services.llm_router import get_llm, current_provider
from app.services.portfolio_analysis_service import PortfolioAnalysisService

logger = logging.getLogger(__name__)

# Same system prompt as AgentCore (from AgentCore/PortfolioInsight/app/PortfolioInsight/main.py)
SYSTEM_PROMPT = """你是 StockMood 的投資陪伴分析師,服務投資新手。

規則(不可違反):
1. 一律使用繁體中文,語氣溫和安撫,像朋友聊天,不用術語轟炸。
2. 絕對不可以出現任何買進、賣出、加碼、減碼、停損等具體操作建議字眼。
3. 只能使用下方提供的實際數字,不得捏造或推算未提供的數值。
4. 資料標記 is_mock=true 時,只能當背景氛圍參考,不可引用其中數字。
5. 資料缺失時,坦白說「這部分資料暫時取不到」,不要編內容。

輸出 JSON(只輸出 JSON,不要其他文字):
{
  "insight_summary": "整體洞察,150 字內,基於風險分數、產業曝險與多維度數據,給使用者「知道自己投組長什麼樣子」的安心感。語氣偏專業分析。",
  "plain_talk": "白話版,80 字內,像跟朋友講話一樣,用最口語的方式把重點講清楚,開頭用「白話說：」,讓沒有投資經驗的人也看得懂。",
  "holding_notes": [
    {"symbol": "代號", "note": "一句話短評,30 字內,偏分析語氣",
     "plain_talk": "白話版短評,30 字內,口語化"}
  ]
}
holding_notes 依權重排序,最多 5 檔。
insight_summary 與 plain_talk 內容不可重複,兩者角度不同:
- insight_summary 偏「發生了什麼事」(分析)
- plain_talk 偏「所以你不用擔心什麼」(安撫)"""

FALLBACK = {
    "insight_summary": "目前分析資料暫時取不到,你的持股數字本身沒有變化,"
    "不用因為看不到分析而緊張;稍後再回來看看就好。",
    "plain_talk": "白話說：資料暫時讀不到,但你的股票都還在,不用擔心。",
    "holding_notes": [],
}


def _gather_data(db: Session, user_id: str) -> dict[str, Any]:
    """Gather the same data that AgentCore tools would fetch, directly from DB."""
    from app.api.routes.internal_tools import (
        get_stock_valuation,
        get_institutional_flow,
        get_stock_momentum,
        get_forum_sentiment,
        get_stock_returns,
    )

    # Get portfolio analysis (rule-based, no AgentCore to avoid circular)
    service = PortfolioAnalysisService(db)
    portfolio = service.get_analysis_raw(user_id)

    # Extract symbols from holdings
    symbols_list = [h["symbol"] for h in portfolio.get("holdings", [])]
    if not symbols_list:
        return {"portfolio": portfolio}

    symbols_str = ",".join(symbols_list[:5])  # top 5 by weight

    data = {"portfolio": portfolio}

    # Gather supplementary data (same as what AgentCore tools would fetch)
    try:
        valuation = get_stock_valuation(symbols=symbols_str, date=None, db=db, user_id=user_id)
        data["valuation"] = valuation.data if valuation.success else []
    except Exception:
        data["valuation"] = []

    try:
        flow = get_institutional_flow(symbols=symbols_str, date=None, db=db, user_id=user_id)
        data["institutional_flow"] = flow.data if flow.success else []
    except Exception:
        data["institutional_flow"] = []

    try:
        momentum = get_stock_momentum(symbols=symbols_str, date=None, db=db, user_id=user_id)
        data["momentum"] = momentum.data if momentum.success else []
    except Exception:
        data["momentum"] = []

    try:
        sentiment = get_forum_sentiment(symbols=symbols_str, date=None, db=db, user_id=user_id)
        data["forum_sentiment"] = sentiment.data if sentiment.success else []
    except Exception:
        data["forum_sentiment"] = []

    try:
        returns = get_stock_returns(symbols=symbols_str, date=None, db=db, user_id=user_id)
        data["returns"] = returns.data if returns.success else []
    except Exception:
        data["returns"] = []

    return data


def _build_user_prompt(data: dict[str, Any], user_id: str) -> str:
    """Build user prompt with all gathered data."""
    portfolio = data["portfolio"]

    parts = [f"使用者 {user_id} 的庫存分析："]
    parts.append(f"- 總市值: {portfolio.get('total_market_value', 0):,.0f}")
    parts.append(f"- 未實現損益: {portfolio.get('unrealized_pnl', 0):,.0f} ({portfolio.get('unrealized_pnl_percent', 0):.2f}%)")
    parts.append(f"- 風險分數: {portfolio.get('risk_score', 0)}")
    parts.append(f"- 科技曝險: {portfolio.get('tech_exposure_percent', 0):.1f}%")
    parts.append("")

    holdings = portfolio.get("holdings", [])
    if holdings:
        parts.append("持股明細（依權重排序）：")
        for h in holdings[:5]:
            parts.append(
                f"  {h['symbol']} {h['name']} | 權重 {h['weight_percent']}% | "
                f"損益 {h['pnl']:+,.0f} ({h['pnl_percent']:+.2f}%) | 今日 {h['change_percent']:+.2f}%"
            )
        parts.append("")

    # Supplementary data
    if data.get("valuation"):
        parts.append("個股估值：")
        for v in data["valuation"][:5]:
            parts.append(f"  {v.get('symbol')} 收盤 {v.get('close_price')} PE {v.get('pe_ratio')} PB {v.get('pb_ratio')}")
        parts.append("")

    if data.get("institutional_flow"):
        parts.append("法人動向：")
        for f in data["institutional_flow"][:5]:
            parts.append(f"  {f.get('symbol')} 外資 {f.get('foreign_net')} 投信 {f.get('trust_net')} 合計 {f.get('total_net')}")
        parts.append("")

    if data.get("momentum"):
        parts.append("動能指標：")
        for m in data["momentum"][:5]:
            parts.append(f"  {m.get('symbol')} 近5日 {m.get('change_5d')}% 近20日 {m.get('change_20d')}% 創新高 {m.get('historical_high')}")
        parts.append("")

    if data.get("forum_sentiment"):
        parts.append("社群討論：")
        for s in data["forum_sentiment"][:5]:
            parts.append(f"  {s.get('symbol')} 發文 {s.get('posts')} 看多 {s.get('bullish')} 看空 {s.get('bearish')}")
        parts.append("")

    parts.append("請根據以上資料產生庫存分析洞察 JSON。")
    return "\n".join(parts)


def _parse_json(raw: str) -> dict:
    """Parse JSON from LLM output, tolerating ```json fences."""
    cleaned = raw.strip()
    if "```" in cleaned:
        cleaned = cleaned.split("```")[1].removeprefix("json").strip()
    start, end = cleaned.find("{"), cleaned.rfind("}")
    if start == -1 or end == -1:
        raise ValueError("no JSON object in model output")
    data = json.loads(cleaned[start: end + 1])
    if "insight_summary" not in data:
        raise ValueError("missing insight_summary")
    data.setdefault("holding_notes", [])
    data.setdefault("plain_talk", "")
    return data


def generate_local_insight(db: Session, user_id: str) -> dict[str, Any]:
    """Generate portfolio insight using the current LLM provider (OpenAI or Claude).

    Gathers data directly from DB (no AgentCore), sends to LLM in one shot.
    Returns same format as AgentCore: {insight_summary, plain_talk, holding_notes}.
    """
    try:
        # 1. Gather all data locally
        data = _gather_data(db, user_id)

        if not data["portfolio"].get("holdings"):
            return FALLBACK

        # 2. Build prompt
        user_prompt = _build_user_prompt(data, user_id)

        # 3. Call LLM (OpenAI or Bedrock depending on X-AI-Provider)
        llm = get_llm()
        raw = llm.converse(
            system=SYSTEM_PROMPT,
            user=user_prompt,
            temperature=0.7,
            max_tokens=1024,
        )

        # 4. Parse response
        result = _parse_json(raw)
        logger.info("Local insight generated via %s for user %s", current_provider(), user_id)
        return result

    except Exception:
        logger.exception("Local insight generation failed for user %s; returning fallback", user_id)
        return FALLBACK
