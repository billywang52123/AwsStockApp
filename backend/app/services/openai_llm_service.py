"""OpenAI Chat Completions text generation service.

Mirrors the ``BedrockLLMService`` interface (``converse`` / ``converse_json``)
so ``OpenAIService`` can swap providers per-request without touching prompts.
Calls are synchronous (httpx) — callers already wrap them with
``run_in_threadpool``, same as the Bedrock path.
"""

from __future__ import annotations

import logging
from typing import Any

import httpx

from app.core.config import settings
from app.services.bedrock_llm_service import BedrockLLMService

logger = logging.getLogger(__name__)

_OPENAI_CHAT_URL = "https://api.openai.com/v1/chat/completions"


class OpenAILLMService:
    """Thin wrapper around OpenAI Chat Completions for text generation."""

    def __init__(self, model: str | None = None):
        self.model = model or settings.OPENAI_MODEL

    def _chat(
        self,
        *,
        system: str,
        user: str,
        temperature: float,
        max_tokens: int,
        json_mode: bool,
    ) -> str:
        if not settings.OPENAI_API_KEY:
            raise RuntimeError("OPENAI_API_KEY is not configured")

        payload: dict[str, Any] = {
            "model": self.model,
            "messages": [
                {"role": "system", "content": system},
                {"role": "user", "content": user},
            ],
            "temperature": temperature,
            "max_tokens": max_tokens,
        }
        if json_mode:
            payload["response_format"] = {"type": "json_object"}

        response = httpx.post(
            _OPENAI_CHAT_URL,
            headers={
                "Authorization": f"Bearer {settings.OPENAI_API_KEY}",
                "Content-Type": "application/json",
            },
            json=payload,
            timeout=30.0,
        )
        response.raise_for_status()
        return response.json()["choices"][0]["message"]["content"]

    def converse(
        self,
        *,
        system: str,
        user: str,
        temperature: float = 0.7,
        max_tokens: int = 1024,
    ) -> str:
        return self._chat(
            system=system, user=user, temperature=temperature,
            max_tokens=max_tokens, json_mode=False,
        )

    def converse_json(
        self,
        *,
        system: str,
        user: str,
        temperature: float = 0.7,
        max_tokens: int = 1024,
    ) -> dict[str, Any]:
        raw = self._chat(
            system=system, user=user, temperature=temperature,
            max_tokens=max_tokens, json_mode=True,
        )
        # Same lenient JSON extraction the Bedrock path uses.
        return BedrockLLMService._parse_json(raw)


_default_service: OpenAILLMService | None = None


def get_openai_llm() -> OpenAILLMService:
    global _default_service
    if _default_service is None:
        _default_service = OpenAILLMService()
    return _default_service
