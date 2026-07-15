"""Bedrock-based push copy generation with a deterministic safe fallback."""

from __future__ import annotations

import json
import logging
import os
from dataclasses import dataclass
from typing import Any

import boto3

from candidate_service import PushCandidate

logger = logging.getLogger(__name__)

_FORBIDDEN_TERMS = (
    "買進",
    "買入",
    "賣出",
    "出售",
    "加碼",
    "減碼",
    "停損",
    "停利",
    "續抱",
    "進場",
    "出場",
    "抄底",
    "逢低",
    "布局",
    "推薦買",
    "建議買",
    "建議賣",
)


@dataclass(frozen=True)
class PushContent:
    title: str
    body: str
    source: str

    def as_dict(self) -> dict[str, str]:
        return {"title": self.title, "body": self.body, "source": self.source}


class BedrockContentService:
    def __init__(self, client: Any | None = None):
        self.model_id = os.environ["BEDROCK_MODEL_ID"]
        self.client = client or boto3.client(
            "bedrock-runtime", region_name=os.getenv("AWS_REGION", "us-east-1")
        )

    @staticmethod
    def fallback(candidate: PushCandidate) -> PushContent:
        direction = "上漲" if candidate.change_percent > 0 else "下跌"
        return PushContent(
            title=f"你持有的{candidate.stock_name}今天有些變化",
            body=(
                f"今天{direction} {abs(candidate.change_percent):.2f}%，"
                "價格變化達到提醒門檻，點進來看看持股資訊。"
            ),
            source="template",
        )

    def generate(self, candidate: PushCandidate, *, enabled: bool = True) -> PushContent:
        fallback = self.fallback(candidate)
        if not enabled:
            return fallback

        system_prompt = """你是 StockMood 的推播文案產生器。只可使用輸入 JSON 中的事實。
請輸出單一 JSON 物件：{\"title\":\"...\",\"body\":\"...\"}。
規則：使用繁體中文；title 最多 30 字；body 最多 70 字；語氣溫和且讓人想點入了解；
不可推測漲跌原因；不可提供買進、賣出、加碼、減碼、停損、停利或任何投資操作建議；
不可輸出 Markdown、額外欄位或 JSON 以外文字。"""
        try:
            response = self.client.converse(
                modelId=self.model_id,
                system=[{"text": system_prompt}],
                messages=[
                    {
                        "role": "user",
                        "content": [
                            {
                                "text": json.dumps(
                                    candidate.facts(), ensure_ascii=False, separators=(",", ":")
                                )
                            }
                        ],
                    }
                ],
                inferenceConfig={"maxTokens": 180, "temperature": 0.2},
            )
            text = "".join(
                block.get("text", "")
                for block in response["output"]["message"]["content"]
                if "text" in block
            )
            content = self._validate(self._parse_json(text))
            return PushContent(title=content["title"], body=content["body"], source="bedrock")
        except Exception:  # noqa: BLE001 - generation must always have a safe fallback
            logger.exception("Bedrock push-content generation failed; using template fallback")
            return fallback

    @staticmethod
    def _parse_json(text: str) -> dict[str, Any]:
        cleaned = text.strip()
        if "```" in cleaned:
            cleaned = cleaned.split("```", 2)[1].removeprefix("json").strip()
        start, end = cleaned.find("{"), cleaned.rfind("}")
        if start < 0 or end < start:
            raise ValueError("Bedrock response did not contain a JSON object")
        parsed = json.loads(cleaned[start : end + 1])
        if not isinstance(parsed, dict):
            raise ValueError("Bedrock response must be a JSON object")
        return parsed

    @staticmethod
    def _validate(content: dict[str, Any]) -> dict[str, str]:
        if set(content) != {"title", "body"}:
            raise ValueError("Bedrock response must contain exactly title and body")
        title = str(content["title"]).strip()
        body = str(content["body"]).strip()
        if not title or not body or len(title) > 30 or len(body) > 70:
            raise ValueError("Bedrock push content exceeded length limits")
        combined = f"{title}{body}"
        if any(term in combined for term in _FORBIDDEN_TERMS):
            raise ValueError("Bedrock push content contained a forbidden investment action")
        return {"title": title, "body": body}
