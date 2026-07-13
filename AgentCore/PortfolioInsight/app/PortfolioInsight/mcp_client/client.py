"""AgentCore Gateway 的 MCP client(SigV4)。

Gateway 用 AWS_IAM inbound auth;URL 由 infra stack 寫入 SSM,
冷啟動讀一次(可用 GATEWAY_URL 環境變數覆寫,本機開發/測試用)。
"""
import logging
import os

import boto3
from mcp_proxy_for_aws.client import aws_iam_streamablehttp_client
from strands.tools.mcp.mcp_client import MCPClient

logger = logging.getLogger(__name__)

REGION = os.environ.get("AWS_REGION", "us-east-1")
GATEWAY_URL_PARAM = "/stockmood/agentcore/gateway-url"

_gateway_url = None


def get_gateway_url() -> str:
    global _gateway_url
    if _gateway_url is None:
        _gateway_url = os.environ.get("GATEWAY_URL") or boto3.client(
            "ssm", region_name=REGION
        ).get_parameter(Name=GATEWAY_URL_PARAM)["Parameter"]["Value"]
    return _gateway_url


def get_gateway_mcp_client() -> MCPClient:
    """Returns a SigV4-signed MCP Client for the StockMood gateway."""
    return MCPClient(
        lambda: aws_iam_streamablehttp_client(
            endpoint=get_gateway_url(),
            aws_region=REGION,
            aws_service="bedrock-agentcore",
        )
    )
