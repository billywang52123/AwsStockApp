#!/usr/bin/env bash
#
# 清除 AgentCore 全部資源:Runtime(CLI 管的 stack)→ Gateway(CDK stack)。
# 用法: AWS_PROFILE=dev ./scripts/destroy.sh
#
# 注意:`agentcore remove all` 會改寫本地 agentcore/agentcore.json;
# destroy 驗證後記得 `git checkout -- PortfolioInsight/agentcore/` 還原設定檔。
set -euo pipefail

PROFILE="${AWS_PROFILE:-dev}"
REGION="us-east-1"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# 1) Runtime:AgentCore CLI 的移除流程 = remove all + 再 deploy(空)套用刪除
cd "$ROOT/PortfolioInsight"
AWS_PROFILE="$PROFILE" agentcore remove all || true
AWS_PROFILE="$PROFILE" agentcore deploy -y || true

# 2) Gateway + Lambdas
cd "$ROOT/infra"
source ../.venv/Scripts/activate 2>/dev/null || source ../.venv/bin/activate
npx cdk destroy StockMood-AgentCoreGateway --profile "$PROFILE" --region "$REGION" --force \
  -c backend_base_url=placeholder

echo "清除完成。用 Tag Editor 檢查 Project=StockMood-Hackathon 是否還有 AgentCore 相關殘留。"
