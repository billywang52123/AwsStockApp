"""Per-request AI provider selection (Claude on Bedrock vs. OpenAI).

The iOS app sends ``X-AI-Provider: claude|openai`` on every request; a
middleware in ``main.py`` stores it in a contextvar so the deepest service
code can pick the right LLM client without threading a parameter through
every call site. Default is Claude — requests without the header behave
exactly as before.
"""

from __future__ import annotations

import contextvars
import logging

from app.core.config import settings

logger = logging.getLogger(__name__)

PROVIDER_CLAUDE = "claude"
PROVIDER_OPENAI = "openai"

_current_provider: contextvars.ContextVar[str] = contextvars.ContextVar(
    "ai_provider", default=PROVIDER_CLAUDE
)


def set_provider_from_header(header_value: str | None) -> contextvars.Token:
    """Parse the X-AI-Provider header and bind it to the current context."""
    value = (header_value or "").strip().lower()
    provider = PROVIDER_OPENAI if value == PROVIDER_OPENAI else PROVIDER_CLAUDE
    return _current_provider.set(provider)


def reset_provider(token: contextvars.Token) -> None:
    _current_provider.reset(token)


def current_provider() -> str:
    return _current_provider.get()


def get_llm():
    """Return the LLM client for the current request's provider.

    Falls back to Bedrock Claude when OpenAI is requested but no API key is
    configured, so the app never breaks on a missing key.
    """
    from app.services.bedrock_llm_service import get_bedrock_llm

    if current_provider() == PROVIDER_OPENAI:
        if settings.OPENAI_API_KEY:
            from app.services.openai_llm_service import get_openai_llm
            return get_openai_llm()
        logger.warning("X-AI-Provider=openai but OPENAI_API_KEY is empty; using Bedrock")
    return get_bedrock_llm()
