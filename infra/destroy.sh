#!/usr/bin/env bash
#
# 清掉 StockMood 全部 AWS 資源(黑客松結束用)。ECR 映像與 RDS 都設 DESTROY,
# 會一併移除。Secrets Manager 密鑰預設有 7 天復原窗口(AWS 政策)。
#
set -euo pipefail
export MSYS_NO_PATHCONV=1

PROFILE="${1:-${AWS_PROFILE:-dev}}"
REGION="${AWS_REGION:-us-east-1}"
INFRA_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "==> 銷毀 StockMood 資源(profile=$PROFILE region=$REGION)"
(cd "$INFRA_DIR" && npx --yes aws-cdk@latest destroy \
  StockMood-EcsExpress StockMood-Data StockMood-Network \
  --profile "$PROFILE" --force)

echo "==> 完成。用 tag 確認殘留:"
echo "    aws resourcegroupstaggingapi get-resources --tag-filters Key=Project,Values=StockMood-Hackathon --profile $PROFILE --region $REGION"
