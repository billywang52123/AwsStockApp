"""AgentCore Runtime 呼叫封裝。

用於需要多工具編排的複雜 AI 分析（個股分析、推播判斷等）。
AgentCore agent 會自動呼叫 get_portfolio_holdings、get_chip_data、
get_market_compare 等工具取得多維度資料再彙整回答。

若 AgentCore 不可用或超時，呼叫端應退回直接 Bedrock 呼叫。
"""

from __future__ import annotations

import json
import logging
import uuid
from typing import Any

import boto3

from app.core.config import settings

logger = logging.getLogger(__name__)


class AgentCoreService:
    """Thin wrapper around Bedrock AgentCore Runtime invoke."""

    def __init__(self, region: str | None = None):
        self._region = region or settings.AWS_REGION
        self._control_client: Any | None = None
        self._client: Any | None = None
        self._runtime_arn: str | None = None

    @property
    def control_client(self) -> Any:
        if self._control_client is None:
            self._control_client = boto3.client(
                "bedrock-agentcore-control", region_name=self._region
            )
        return self._control_client

    @property
    def client(self) -> Any:
        if self._client is None:
            self._client = boto3.client(
                "bedrock-agentcore", region_name=self._region
            )
        return self._client

    @property
    def runtime_arn(self) -> str:
        """Lazily discover the PortfolioInsight runtime ARN."""
        if self._runtime_arn is None:
            if settings.AGENTCORE_RUNTIME_ARN:
                self._runtime_arn = settings.AGENTCORE_RUNTIME_ARN
            else:
                runtimes = self.control_client.list_agent_runtimes()["agentRuntimes"]
                matches = [
                    r for r in runtimes
                    if "portfolioinsight" in r["agentRuntimeName"].lower()
                ]
                if not matches:
                    raise RuntimeError(
                        f"No PortfolioInsight runtime found. Available: "
                        f"{[r['agentRuntimeName'] for r in runtimes]}"
                    )
                self._runtime_arn = matches[0]["agentRuntimeArn"]
                logger.info("Discovered AgentCore runtime: %s", self._runtime_arn)
        return self._runtime_arn

    def invoke(self, payload: dict[str, Any]) -> dict[str, Any]:
        """Invoke AgentCore Runtime and return parsed JSON response.

        Raises on any error (timeout, parse failure, etc.) so callers can fallback.
        """
        resp = self.client.invoke_agent_runtime(
            agentRuntimeArn=self.runtime_arn,
            runtimeSessionId=str(uuid.uuid4()),
            payload=json.dumps(payload).encode(),
            qualifier="DEFAULT",
        )
        body = "".join(chunk.decode() for chunk in resp.get("response", []))
        data = json.loads(body)
        return data

    def get_stock_insight(self, user_id: str) -> dict[str, Any] | None:
        """Get portfolio insight for a user via AgentCore.

        Returns the agent's response dict with insight_summary and holding_notes,
        or None if the call fails.
        """
        try:
            result = self.invoke({"user_id": user_id})
            if "insight_summary" in result:
                logger.info("AgentCore insight generated for user %s", user_id)
                return result
            logger.warning("AgentCore response missing insight_summary: %s", result)
        except Exception:
            logger.exception("AgentCore invoke failed for user %s", user_id)
        return None


# Module-level singleton
_service: AgentCoreService | None = None


def get_agentcore_service() -> AgentCoreService:
    global _service
    if _service is None:
        _service = AgentCoreService()
    return _service
