#!/usr/bin/env bash
#
# 部署 AgentCore Gateway + Lambda tools(us-east-1)。
# 用法: BACKEND_BASE_URL=https://... ./scripts/deploy_gateway.sh [profile]
set -euo pipefail

PROFILE="${1:-${AWS_PROFILE:-dev}}"
REGION="us-east-1"
INFRA_DIR="$(cd "$(dirname "$0")/../infra" && pwd)"

if [[ -z "${BACKEND_BASE_URL:-}" ]]; then
  echo "ERROR: 請設 BACKEND_BASE_URL(ECS Express 每次重部署會換網域,先確認現值)" >&2
  exit 1
fi

cd "$INFRA_DIR"
if [[ ! -d ../.venv ]]; then python -m venv ../.venv; fi
source ../.venv/Scripts/activate 2>/dev/null || source ../.venv/bin/activate
pip install -q -r requirements.txt

npx cdk deploy StockMood-AgentCoreGateway \
  --profile "$PROFILE" --region "$REGION" \
  -c backend_base_url="$BACKEND_BASE_URL" \
  --require-approval never

echo "Gateway URL:"
# MSYS_NO_PATHCONV 只加在這一條:Git Bash 會把開頭是 / 的參數名誤轉成本機路徑
MSYS_NO_PATHCONV=1 aws ssm get-parameter --name /stockmood/agentcore/gateway-url \
  --profile "$PROFILE" --region "$REGION" --query Parameter.Value --output text
