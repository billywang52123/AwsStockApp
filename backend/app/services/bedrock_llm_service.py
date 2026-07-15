"""Unified Bedrock Runtime text generation service (Converse API).

Replaces all OpenAI GPT-4o-mini calls with Claude Sonnet 4.5 via AWS Bedrock.
boto3 Converse is synchronous; callers in async FastAPI routes should wrap
calls with ``starlette.concurrency.run_in_threadpool``.
"""

from __future__ import annotations

import json
import logging
from typing import Any

import boto3

from app.core.config import settings

logger = logging.getLogger(__name__)


class BedrockLLMService:
    """Thin wrapper around Bedrock Runtime Converse for text generation."""

    def __init__(self, model_id: str | None = None, region: str | None = None):
        self.model_id = model_id or settings.BEDROCK_TEXT_MODEL_ID
        self._region = region or settings.AWS_REGION
        self._client: Any | None = None

    @property
    def client(self) -> Any:
        if self._client is None:
            self._client = boto3.client("bedrock-runtime", region_name=self._region)
        return self._client

    def converse(
        self,
        *,
        system: str,
        user: str,
        temperature: float = 0.7,
        max_tokens: int = 1024,
    ) -> str:
        """Call Bedrock Converse and return the assistant's text response.

        Raises on network/API errors so callers can fall back gracefully.
        """
        response = self.client.converse(
            modelId=self.model_id,
            system=[{"text": system}],
            messages=[
                {"role": "user", "content": [{"text": user}]},
            ],
            inferenceConfig={"maxTokens": max_tokens, "temperature": temperature},
        )
        text = "".join(
            block.get("text", "")
            for block in response["output"]["message"]["content"]
            if "text" in block
        )
        return text

    def converse_json(
        self,
        *,
        system: str,
        user: str,
        temperature: float = 0.7,
        max_tokens: int = 1024,
    ) -> dict[str, Any]:
        """Call Converse and parse the response as JSON.

        The system prompt should instruct the model to return only JSON.
        Handles markdown code fences and extracts the first JSON object.
        Raises ValueError if parsing fails.
        """
        raw = self.converse(
            system=system, user=user, temperature=temperature, max_tokens=max_tokens
        )
        return self._parse_json(raw)

    @staticmethod
    def _parse_json(text: str) -> dict[str, Any]:
        cleaned = text.strip()
        if "```" in cleaned:
            # Extract content between first pair of triple backticks
            parts = cleaned.split("```")
            if len(parts) >= 3:
                cleaned = parts[1]
                if cleaned.startswith("json"):
                    cleaned = cleaned[4:]
                cleaned = cleaned.strip()
        start = cleaned.find("{")
        end = cleaned.rfind("}")
        if start < 0 or end < start:
            raise ValueError(f"No JSON object found in Bedrock response: {text[:200]}")
        parsed = json.loads(cleaned[start : end + 1])
        if not isinstance(parsed, dict):
            raise ValueError("Bedrock response is not a JSON object")
        return parsed


# Module-level singleton (lazy client creation)
_default_service: BedrockLLMService | None = None


def get_bedrock_llm() -> BedrockLLMService:
    """Return the module-level BedrockLLMService singleton."""
    global _default_service
    if _default_service is None:
        _default_service = BedrockLLMService()
    return _default_service
