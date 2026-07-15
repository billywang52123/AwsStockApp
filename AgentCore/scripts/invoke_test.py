"""從本機 invoke 已部署的 AgentCore Runtime,人工檢查洞察品質。

用法: AWS_PROFILE=dev python scripts/invoke_test.py --user-id demo-user
"""
import argparse
import json
import uuid

import boto3

REGION = "us-east-1"


def find_runtime_arn(client) -> str:
    runtimes = client.list_agent_runtimes()["agentRuntimes"]
    matches = [r for r in runtimes if "portfolioinsight" in r["agentRuntimeName"].lower()]
    assert matches, f"找不到 PortfolioInsight runtime,現有: {[r['agentRuntimeName'] for r in runtimes]}"
    return matches[0]["agentRuntimeArn"]


def main(user_id: str) -> None:
    control = boto3.client("bedrock-agentcore-control", region_name=REGION)
    arn = find_runtime_arn(control)
    print(f"Runtime: {arn}")

    client = boto3.client("bedrock-agentcore", region_name=REGION)
    resp = client.invoke_agent_runtime(
        agentRuntimeArn=arn,
        runtimeSessionId=str(uuid.uuid4()),
        payload=json.dumps({"user_id": user_id}).encode(),
        qualifier="DEFAULT",
    )
    raw = b"".join(chunk for chunk in resp.get("response", []))
    body = raw.decode("utf-8")
    data = json.loads(body)
    print(json.dumps(data, ensure_ascii=False, indent=2))

    assert "insight_summary" in data, "缺 insight_summary"
    banned = ["買進", "賣出", "加碼", "減碼", "停損"]
    text = json.dumps(data, ensure_ascii=False)
    hits = [w for w in banned if w in text]
    assert not hits, f"出現禁用字眼: {hits}"
    print("INVOKE OK")


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("--user-id", default="demo-user")
    main(p.parse_args().user_id)
