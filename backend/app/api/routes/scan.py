import base64
import json
from fastapi import APIRouter, Depends, UploadFile, File, HTTPException
from openai import AsyncOpenAI
from sqlalchemy.orm import Session
from app.core.auth import get_current_user_id
from app.core.config import settings
from app.db.database import get_db
from pydantic import BaseModel
from typing import Optional

router = APIRouter()

class ScannedStock(BaseModel):
    symbol: str
    name: str
    shares: Optional[str] = None
    cost: Optional[str] = None

class ScanReceiptResponse(BaseModel):
    success: bool
    stocks: list[ScannedStock]
    raw_text: Optional[str] = None
    message: Optional[str] = None

SYSTEM_PROMPT = """你是一個專業的台灣股票對帳單 OCR 助理。
使用者會上傳對帳單圖片，你需要從圖片中識別以下資訊：
1. 股票代號（如 2330、0050 等）
2. 股票名稱（如 台積電、元大台灣50 等）
3. 持有股數（單位：股）
4. 平均成本/買入均價（單位：新台幣元）

請以 JSON 格式回傳，格式如下：
{
  "stocks": [
    {
      "symbol": "2330",
      "name": "台積電",
      "shares": "1000",
      "cost": "920.5"
    }
  ],
  "raw_text": "從圖片識別到的原始文字"
}

注意事項：
- 如果圖片模糊或無法識別，stocks 回傳空陣列
- 股票代號只包含數字（台灣股票）
- shares 和 cost 用字串格式
- 如果無法確定某欄位，該欄位填 null
- 只回傳 JSON，不要加任何額外說明
"""

@router.post("/scan/receipt", response_model=ScanReceiptResponse)
async def scan_stock_receipt(
    file: UploadFile = File(...),
    source: Optional[str] = None,  # "camera"（拍攝對帳單）或 "photo"（相簿截圖）
    db: Session = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
):
    """
    Use GPT-4o-mini Vision to OCR a brokerage statement image and extract stock holdings.
    """
    if not settings.OPENAI_API_KEY:
        raise HTTPException(
            status_code=503,
            detail="OpenAI API Key 尚未設定，無法使用 AI 對帳單識別功能"
        )

    # Validate file type
    content_type = file.content_type or ""
    if not content_type.startswith("image/"):
        raise HTTPException(
            status_code=400,
            detail="請上傳圖片檔案（JPG、PNG 等）"
        )

    # Read and encode image
    image_data = await file.read()
    if len(image_data) > 10 * 1024 * 1024:  # 10MB limit
        raise HTTPException(status_code=400, detail="圖片大小不能超過 10MB")

    base64_image = base64.b64encode(image_data).decode("utf-8")

    # Determine MIME type for data URL
    if "jpeg" in content_type or "jpg" in content_type:
        mime = "image/jpeg"
    elif "png" in content_type:
        mime = "image/png"
    elif "heic" in content_type or "heif" in content_type:
        mime = "image/jpeg"  # HEIC converted to JPEG on iOS before upload
    else:
        mime = "image/jpeg"

    # Call GPT-4o-mini Vision
    client = AsyncOpenAI(api_key=settings.OPENAI_API_KEY)
    try:
        response = await client.chat.completions.create(
            model="gpt-4o-mini",
            messages=[
                {
                    "role": "system",
                    "content": SYSTEM_PROMPT
                },
                {
                    "role": "user",
                    "content": [
                        {
                            "type": "image_url",
                            "image_url": {
                                "url": f"data:{mime};base64,{base64_image}",
                                "detail": "high"
                            }
                        },
                        {
                            "type": "text",
                            "text": "請識別這張對帳單圖片中的所有持股資訊，包含股票代號、名稱、持股數量和成本。"
                        }
                    ]
                }
            ],
            max_tokens=1000,
            temperature=0.1,
        )

        raw_content = response.choices[0].message.content or ""

        # Parse JSON from GPT response
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
                raw_text=raw_text,
                message=f"成功識別 {len(stocks)} 筆持股"
            )

        except (json.JSONDecodeError, KeyError) as e:
            # GPT returned non-JSON — try to extract what we can
            return ScanReceiptResponse(
                success=len(stocks_data) > 0 if 'stocks_data' in dir() else False,
                stocks=[],
                raw_text=raw_content,
                message="AI 識別格式異常，請重試或手動輸入"
            )

    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"AI 分析失敗：{str(e)}"
        )
