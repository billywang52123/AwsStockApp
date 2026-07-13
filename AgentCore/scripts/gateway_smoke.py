"""Gateway 煙霧測試:SigV4 連 MCP endpoint,列工具、實呼叫 get_portfolio_holdings。

用法: AWS_PROFILE=dev python scripts/gateway_smoke.py [--user-id demo-user]
需要: pip install mcp-proxy-for-aws (含 mcp 依賴)
"""
import argparse
import asyncio
import json

import boto3
from mcp import ClientSession
from mcp_proxy_for_aws.client import aws_iam_streamablehttp_client

REGION = "us-east-1"
PARAM = "/stockmood/agentcore/gateway-url"


async def main(user_id: str) -> None:
    gateway_url = boto3.client("ssm", region_name=REGION).get_parameter(Name=PARAM)[
        "Parameter"
    ]["Value"]
    print(f"Gateway: {gateway_url}")

    async with aws_iam_streamablehttp_client(
        endpoint=gateway_url, aws_region=REGION, aws_service="bedrock-agentcore"
    ) as (read, write, _):
        async with ClientSession(read, write) as session:
            await session.initialize()
            tools = await session.list_tools()
            names = [t.name for t in tools.tools]
            print(f"tools ({len(names)}): {names}")
            assert len(names) == 4, "應有 4 個工具"

            holdings_tool = next(n for n in names if "get_portfolio_holdings" in n)
            result = await session.call_tool(holdings_tool, {"user_id": user_id})
            payload = json.loads(result.content[0].text)
            print(json.dumps(payload, ensure_ascii=False, indent=2)[:800])
            assert "error" not in payload, f"工具回錯誤: {payload}"
            assert "risk_score" in payload, "應含規則式風險分數"
    print("SMOKE OK")


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("--user-id", default="demo-user")
    asyncio.run(main(p.parse_args().user_id))
