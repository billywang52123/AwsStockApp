#!/usr/bin/env bash
#
# 部署 PortfolioInsight agent 到 AgentCore Runtime,並補 runtime 角色權限
# (讀 SSM gateway-url + SigV4 invoke gateway)。
# 用法: AWS_PROFILE=dev ./scripts/deploy_runtime.sh
#       角色名撈不到時: RUNTIME_ROLE_NAME=<role> AWS_PROFILE=dev ./scripts/deploy_runtime.sh
set -euo pipefail

PROFILE="${AWS_PROFILE:-dev}"
REGION="us-east-1"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

cd "$ROOT/PortfolioInsight"
AWS_PROFILE="$PROFILE" agentcore deploy -y

# ── 補 runtime 執行角色權限 ──────────────────────────────────
ACCOUNT=$(aws sts get-caller-identity --profile "$PROFILE" --query Account --output text)
GATEWAY_ARN=$(aws cloudformation describe-stacks --stack-name StockMood-AgentCoreGateway \
  --profile "$PROFILE" --region "$REGION" \
  --query "Stacks[0].Outputs[?OutputKey=='GatewayArn'].OutputValue" --output text)

if [[ -z "${RUNTIME_ROLE_NAME:-}" ]]; then
  # 注意:CloudFormation 會截斷角色名(實測是 AgentCore-PortfolioInsigh-...,少一個 t),
  # 所以用較短的 'PortfolioInsigh' 找
  RUNTIME_ROLE_NAME=$(aws iam list-roles --profile "$PROFILE" \
    --query "Roles[?contains(RoleName, 'PortfolioInsigh')].RoleName | [0]" --output text)
fi
if [[ "$RUNTIME_ROLE_NAME" == "None" || -z "$RUNTIME_ROLE_NAME" ]]; then
  echo "ERROR: 找不到 runtime 執行角色;用 'agentcore status' 確認後以 RUNTIME_ROLE_NAME 傳入重跑" >&2
  exit 1
fi
echo "Runtime role: $RUNTIME_ROLE_NAME"

MSYS_NO_PATHCONV=1 aws iam put-role-policy --profile "$PROFILE" --role-name "$RUNTIME_ROLE_NAME" \
  --policy-name stockmood-gateway-access \
  --policy-document "{
    \"Version\": \"2012-10-17\",
    \"Statement\": [
      {\"Effect\": \"Allow\", \"Action\": \"ssm:GetParameter\",
       \"Resource\": \"arn:aws:ssm:$REGION:$ACCOUNT:parameter/stockmood/agentcore/gateway-url\"},
      {\"Effect\": \"Allow\", \"Action\": \"bedrock-agentcore:*\",
       \"Resource\": \"$GATEWAY_ARN*\"}
    ]
  }"
echo "Runtime deployed. 用 scripts/invoke_test.py 驗證。"
