"""語音持股輸入 AI 解析 — spec 08 · 19a–19c。

iPhone 端 SFSpeechRecognizer(裝置端)轉出的逐字稿(純文字)→ Bedrock Claude NLU
→ 結構化持股陣列。錄音檔不上傳、不落地,後端只經手文字。

解析結果逐檔用本地 stocks 表 / CMoney 模擬資料驗證(沿用 ai_screen 的驗證模式):
- 代號驗證通過 → confidence="high"
- 代號對不到但名稱搜尋唯一命中 → 以搜尋結果為準,confidence="high"
- 都對不到 → confidence="low",保留原話讓前端顯示金色低信心卡,由用戶修正
"""

from __future__ import annotations

import logging
from typing import Any, Optional

from sqlalchemy.orm import Session

from app.services.llm_router import get_llm
from app.services.services import StockService

logger = logging.getLogger(__name__)

# 安撫語氣失敗文案(spec 08:失敗不用錯誤紅)
PARSE_RETRY_MESSAGE = "沒聽清楚,再說一次試試"

_SYSTEM_PROMPT = """你是台股持股語音輸入的解析引擎。使用者用口語描述想記錄的持股,你要輸出結構化 JSON。

規則:
1. 只輸出一個 JSON 物件,格式:
   {"items":[{"mention":"句中對這檔股票的稱呼","symbol":"台股代號(4-6碼,不確定給null)","shares":股數整數或null,"cost_price":每股成本數字或null,"note":"換算說明或null"}]}
2. 台股量詞「張」= 1,000 股:「一張」=1000、「兩張」=2000、「半張」=500;零股直接用股數。
3. 口語數字要換算成阿拉伯數字:「九百八」=980、「六十五塊半」=65.5、「一千二」=1200。
4. 有做任何量詞或口語數字換算時,在 note 用一句話註明依據,格式例:「『兩張』= 2,000 股 ·『九百八』= 成本 980 元」;完全沒換算給 null。
5. 沒提到成本就給 null,不要猜;沒提到股數也給 null。
6. 股票稱呼對不到有把握的台股代號時 symbol 給 null,mention 保留原話。
7. 一句話可能提到多檔股票,每檔一筆。
8. 內容與持股記錄無關時輸出 {"items":[]}。
9. note 與任何欄位都不可出現投資建議或買進賣出等操作字眼,只做輸入內容的換算說明。"""

MAX_TRANSCRIPT_CHARS = 500
MAX_ITEMS = 10
MAX_SHARES = 1_000_000_000
MAX_PRICE = 10_000_000


def _to_int(value: Any) -> Optional[int]:
    try:
        n = int(float(value))
    except (TypeError, ValueError):
        return None
    return n if 0 < n <= MAX_SHARES else None


def _to_price(value: Any) -> Optional[float]:
    try:
        p = float(value)
    except (TypeError, ValueError):
        return None
    return p if 0 < p <= MAX_PRICE else None


def parse_voice_holdings(db: Session, text: str) -> dict:
    """逐字稿 → {"transcript", "items", "message"}。

    LLM 或解析失敗時不拋例外,回空 items + 安撫文案,由前端引導重說/手動輸入。
    """
    transcript = (text or "").strip()[:MAX_TRANSCRIPT_CHARS]
    if not transcript:
        return {"transcript": transcript, "items": [], "message": PARSE_RETRY_MESSAGE}

    try:
        parsed = get_llm().converse_json(
            system=_SYSTEM_PROMPT, user=transcript, temperature=0.1, max_tokens=1024
        )
        raw_items = parsed.get("items", [])
    except Exception:
        logger.exception("Voice holdings parse (LLM) failed")
        return {"transcript": transcript, "items": [], "message": PARSE_RETRY_MESSAGE}

    service = StockService(db)
    items: list[dict] = []
    seen: set[str] = set()
    for cand in raw_items:
        if not isinstance(cand, dict):
            continue
        mention = str(cand.get("mention") or "").strip()
        symbol = str(cand.get("symbol") or "").strip().upper()
        shares = _to_int(cand.get("shares"))
        cost_price = _to_price(cand.get("cost_price"))
        note = str(cand.get("note") or "").strip() or None

        stock = _resolve_stock(service, symbol, mention)
        if stock is not None:
            if stock.symbol in seen:
                continue
            seen.add(stock.symbol)
            items.append({
                "symbol": stock.symbol,
                "name": stock.name,
                "mention": mention or stock.name,
                "shares": shares,
                "cost_price": cost_price,
                "note": note,
                "confidence": "high",
            })
        elif mention or symbol:
            # 對不到台股代號 → 低信心卡,保留原話由用戶改
            items.append({
                "symbol": None,
                "name": None,
                "mention": mention or symbol,
                "shares": shares,
                "cost_price": cost_price,
                "note": note,
                "confidence": "low",
            })
        if len(items) >= MAX_ITEMS:
            break

    message = PARSE_RETRY_MESSAGE if not items else None
    return {"transcript": transcript, "items": items, "message": message}


def _resolve_stock(service: StockService, symbol: str, mention: str):
    """LLM 給的代號優先,查無時退回名稱搜尋(唯一命中才採用)。"""
    if symbol:
        stock = service.repo.get_stock(symbol)
        if stock:
            return stock
        if symbol.isdigit() and 4 <= len(symbol) <= 6:
            stock = service._import_unknown_symbol(symbol)
            if stock:
                return stock
    if mention:
        results = service.search_stocks(mention) or []
        exact = [s for s in results if s.name == mention or s.symbol == mention]
        if len(exact) == 1:
            return exact[0]
        if len(results) == 1:
            return results[0]
    return None
