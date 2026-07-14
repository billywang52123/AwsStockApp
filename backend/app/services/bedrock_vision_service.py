"""對帳單 OCR 的 Bedrock Vision 呼叫(取代原本的 OpenAI Vision)。

以 Bedrock Runtime 的 Converse API 傳入影像 bytes,回模型輸出的原始文字;
JSON 解析與 fallback 仍由 scan.py 處理,本服務只負責「圖片進、文字出」。
"""

import logging

import boto3

from app.core.config import settings

logger = logging.getLogger(__name__)

SYSTEM_PROMPT = """你是一個專業的台灣股票對帳單 OCR 助理。
使用者會上傳對帳單圖片，你需要從圖片中識別以下資訊：
1. 股票代號（如 2330、0050 等）
2. 股票名稱（如 台積電、元大台灣50 等）
3. 持有股數（單位：股）
4. 平均成本/買入均價（單位：新台幣元）
5. 券商名稱（從 App 介面 logo、標題列或對帳單抬頭判斷，如 富邦證券、國泰證券、元大證券、凱基證券、永豐金證券 等）

請以 JSON 格式回傳，格式如下：
{
  "stocks": [
    {"symbol": "2330", "name": "台積電", "shares": "1000", "cost": "920.5"}
  ],
  "broker": "富邦證券",
  "raw_text": "從圖片識別到的原始文字"
}

注意事項：
- 如果圖片模糊或無法識別，stocks 回傳空陣列
- 股票代號只包含數字（台灣股票）
- shares 和 cost 用字串格式
- 如果無法確定某欄位，該欄位填 null（包含 broker 無法判斷時）
- 只回傳 JSON，不要加任何額外說明
"""


def _content_type_to_format(content_type: str) -> str:
    ct = (content_type or "").lower()
    if "png" in ct:
        return "png"
    if "webp" in ct:
        return "webp"
    if "gif" in ct:
        return "gif"
    # jpg/jpeg 及 iOS 已轉 jpeg 的 heic/heif 都當 jpeg
    return "jpeg"


class BedrockVisionService:
    @staticmethod
    def _client():
        return boto3.client("bedrock-runtime", region_name=settings.AWS_REGION)

    @classmethod
    def extract_receipt_text(cls, image_bytes: bytes, content_type: str) -> str:
        """呼叫 Bedrock Vision 辨識對帳單,回原始模型文字。失敗時拋例外。"""
        fmt = _content_type_to_format(content_type)
        resp = cls._client().converse(
            modelId=settings.BEDROCK_VISION_MODEL_ID,
            system=[{"text": SYSTEM_PROMPT}],
            messages=[
                {
                    "role": "user",
                    "content": [
                        {"image": {"format": fmt, "source": {"bytes": image_bytes}}},
                        {"text": "請識別這張對帳單圖片中的所有持股資訊，包含股票代號、名稱、持股數量和成本。"},
                    ],
                }
            ],
            inferenceConfig={"maxTokens": 1000, "temperature": 0.1},
        )
        return resp["output"]["message"]["content"][0]["text"] or ""
