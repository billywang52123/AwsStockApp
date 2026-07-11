import base64
import json
import logging
import time
from collections import defaultdict, deque
from fastapi import APIRouter, Depends, UploadFile, File, HTTPException
from sqlalchemy.orm import Session
from starlette.concurrency import run_in_threadpool
from app.core.auth import get_current_user_id
from app.db.database import get_db
from app.services.bedrock_vision_service import BedrockVisionService
from pydantic import BaseModel
from typing import Optional

logger = logging.getLogger(__name__)

router = APIRouter()

# Per-user sliding-window rate limit: each OCR call costs real Bedrock money.
SCAN_RATE_LIMIT = 15          # requests
SCAN_RATE_WINDOW = 60 * 60    # per hour
_scan_history: dict[str, deque] = defaultdict(deque)


def _check_scan_rate_limit(user_id: str) -> None:
    now = time.monotonic()
    history = _scan_history[user_id]
    while history and now - history[0] > SCAN_RATE_WINDOW:
        history.popleft()
    if len(history) >= SCAN_RATE_LIMIT:
        raise HTTPException(
            status_code=429,
            detail="掃描次數已達上限，請一小時後再試"
        )
    history.append(now)

class ScannedStock(BaseModel):
    symbol: str
    name: str
    shares: Optional[str] = None
    cost: Optional[str] = None

class ScanReceiptResponse(BaseModel):
    success: bool
    stocks: list[ScannedStock]
    # 對帳單所屬券商(9d 匯入合併「來源 chip」用;辨識不出時為 None,由前端要求用戶補選)
    broker: Optional[str] = None
    raw_text: Optional[str] = None
    message: Optional[str] = None

@router.post("/scan/receipt", response_model=ScanReceiptResponse)
async def scan_stock_receipt(
    file: UploadFile = File(...),
    source: Optional[str] = None,  # "camera"（拍攝對帳單）或 "photo"（相簿截圖）
    db: Session = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
):
    """
    Use Bedrock Vision (Claude) to OCR a brokerage statement image and extract stock holdings.
    """
    _check_scan_rate_limit(user_id)

    # Validate file type
    content_type = file.content_type or ""
    if not content_type.startswith("image/"):
        raise HTTPException(
            status_code=400,
            detail="請上傳圖片檔案（JPG、PNG 等）"
        )

    # Read image.
    # 隱私保證(spec 05):圖片只存在這個 request 的記憶體裡 —— 不寫入磁碟、
    # 不寫入 log、不進資料庫;request 結束即釋放。錯誤時只記例外堆疊,不含圖片內容。
    image_data = await file.read()
    if len(image_data) > 10 * 1024 * 1024:  # 10MB limit
        raise HTTPException(status_code=400, detail="圖片大小不能超過 10MB")

    # Call Bedrock Vision (sync boto3 client, so run in threadpool)
    try:
        raw_content = await run_in_threadpool(
            BedrockVisionService.extract_receipt_text, image_data, content_type
        )
    except Exception:
        # Log the real error server-side; never echo internals back to the client
        logger.exception("Receipt scan (Bedrock) failed for user %s", user_id)
        raise HTTPException(
            status_code=500,
            detail="AI 分析失敗，請稍後再試"
        )

    # Parse JSON from model response
    try:
        # Strip markdown code blocks if present
        cleaned = raw_content.strip()
        if cleaned.startswith("```"):
            cleaned = cleaned.split("```")[1]
            if cleaned.startswith("json"):
                cleaned = cleaned[4:]
            cleaned = cleaned.strip()

        parsed = json.loads(cleaned)
        stocks_data = parsed.get("stocks", [])
        broker = parsed.get("broker") or None
        raw_text = parsed.get("raw_text", "")

        stocks = [
            ScannedStock(
                symbol=s.get("symbol", ""),
                name=s.get("name", ""),
                shares=str(s["shares"]) if s.get("shares") else None,
                cost=str(s["cost"]) if s.get("cost") else None
            )
            for s in stocks_data
            if s.get("symbol")
        ]

        # OCR import achievements
        if stocks:
            from app.services.services import AchievementService
            ach = AchievementService(db)
            ach.trigger_unlock("IMPORT_FIRST_OCR", user_id)
            if source == "photo":
                ach.trigger_unlock("IMPORT_SCREENSHOT", user_id)
            elif source == "camera":
                ach.trigger_unlock("IMPORT_RECEIPT", user_id)
            if len(stocks) >= 10:
                ach.trigger_unlock("IMPORT_CLEAN_10", user_id)
            if len(stocks) >= 30:
                ach.trigger_unlock("IMPORT_FAMILY_BUCKET", user_id)

        return ScanReceiptResponse(
            success=True,
            stocks=stocks,
            broker=broker,
            raw_text=raw_text,
            message=f"成功識別 {len(stocks)} 筆持股"
        )

    except (json.JSONDecodeError, KeyError):
        # Model returned non-JSON — surface raw text so the client can retry / manual input
        return ScanReceiptResponse(
            success=False,
            stocks=[],
            raw_text=raw_content,
            message="AI 識別格式異常，請重試或手動輸入"
        )
