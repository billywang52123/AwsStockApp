#!/usr/bin/env bash
#
# StockMood — 一鍵部署到 AWS(us-east-1)。
#
# 把「純 cdk deploy 之外」的手動前置全部串起來,讓乾淨帳號也能一次到位:
#   bootstrap → SLR → deploy Network/Data → build+push 映像 → 填密鑰 → deploy ECS Express
#
# 用法:
#   AWS_PROFILE=dev ./deploy.sh
#   (或)  ./deploy.sh dev
#
# 前置需求(腳本不會幫你裝):
#   - AWS CLI 已設定該 profile 的憑證
#   - Node.js(cdk CLI 用 npx 取得)
#   - Python venv(見下方 auto-setup)
#   - podman 或 docker(build 映像)
#   - us-east-1 已在 Bedrock console 開通所用視覺模型的存取(若帳號預設未開)
#
set -euo pipefail

PROFILE="${1:-${AWS_PROFILE:-dev}}"
REGION="${AWS_REGION:-us-east-1}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
BACKEND_DIR="$(cd "$(dirname "$0")/../backend" && pwd)"
INFRA_DIR="$(cd "$(dirname "$0")" && pwd)"

# 容器工具:優先 podman,退而 docker
if command -v podman >/dev/null 2>&1; then CONTAINER=podman
elif command -v docker >/dev/null 2>&1; then CONTAINER=docker
else echo "ERROR: 需要 podman 或 docker"; exit 1; fi

aws() { command aws --profile "$PROFILE" --region "$REGION" "$@"; }
cdk() { (cd "$INFRA_DIR" && npx --yes aws-cdk@latest "$@" --profile "$PROFILE"); }

echo "==> Profile=$PROFILE Region=$REGION Container=$CONTAINER"
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
ECR_URI="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/stockmood-api"
echo "==> Account=$ACCOUNT_ID"

echo "==> [1/8] Python venv + CDK deps"
if [ ! -d "$INFRA_DIR/.venv" ]; then python -m venv "$INFRA_DIR/.venv"; fi
"$INFRA_DIR/.venv/Scripts/python.exe" -m pip install -q -r "$INFRA_DIR/requirements.txt" 2>/dev/null \
  || "$INFRA_DIR/.venv/bin/python" -m pip install -q -r "$INFRA_DIR/requirements.txt"

echo "==> [2/8] CDK bootstrap(一次性,已 bootstrap 會直接略過)"
cdk bootstrap "aws://${ACCOUNT_ID}/${REGION}" >/dev/null

echo "==> [3/8] Service-linked roles(已存在則忽略)"
aws iam create-service-linked-role --aws-service-name ecs.amazonaws.com >/dev/null 2>&1 || true
aws iam create-service-linked-role --aws-service-name ecs.application-autoscaling.amazonaws.com >/dev/null 2>&1 || true

echo "==> [4/8] Deploy Network + Data(先要有 ECR 才能推映像)"
cdk deploy StockMood-Network StockMood-Data --require-approval never >/dev/null

echo "==> [5/8] 填 app 密鑰(缺 key 才補;OPENAI 先留空 → 走規則式 fallback)"
if ! aws secretsmanager get-secret-value --secret-id stockmood/app \
      --query SecretString --output text 2>/dev/null | grep -q 'JWT_SECRET'; then
  JWT="$(python -c 'import secrets;print(secrets.token_urlsafe(48))')"
  ADMIN="$(python -c 'import secrets;print(secrets.token_urlsafe(24))')"
  aws secretsmanager put-secret-value --secret-id stockmood/app \
    --secret-string "{\"OPENAI_API_KEY\":\"\",\"JWT_SECRET\":\"$JWT\",\"ADMIN_API_KEY\":\"$ADMIN\"}" >/dev/null
  echo "    -> 已寫入新的 JWT_SECRET / ADMIN_API_KEY(OPENAI_API_KEY 空)"
else
  echo "    -> 密鑰已存在,略過"
fi

echo "==> [6/8] Build + push 映像($CONTAINER, linux/amd64)"
aws ecr get-login-password | "$CONTAINER" login --username AWS --password-stdin "${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"
"$CONTAINER" build --platform linux/amd64 -t "${ECR_URI}:${IMAGE_TAG}" "$BACKEND_DIR"
"$CONTAINER" push "${ECR_URI}:${IMAGE_TAG}"

echo "==> [7/8] Deploy ECS Express"
cdk deploy StockMood-EcsExpress --require-approval never >/dev/null

echo "==> [8/8] 強制滾動最新映像(cdk 對同 tag 不會偵測變更)"
aws ecs update-service --cluster default --service stockmood-api --force-new-deployment >/dev/null
aws ecs wait services-stable --cluster default --services stockmood-api

# 取 ECS Express 產生的公開網域(ALB listener 的 host-header 規則)
VPC="$(aws ec2 describe-vpcs --filters "Name=tag:Project,Values=StockMood-Hackathon" --query 'Vpcs[0].VpcId' --output text)"
ALB="$(aws elbv2 describe-load-balancers --query "LoadBalancers[?VpcId=='$VPC'].LoadBalancerArn" --output text)"
LISTENER="$(aws elbv2 describe-listeners --load-balancer-arn "$ALB" --query 'Listeners[0].ListenerArn' --output text)"
HOST="$(aws elbv2 describe-rules --listener-arn "$LISTENER" --query "Rules[?Priority=='1'].Conditions[0].Values[0]" --output text)"

echo ""
echo "======================================================================"
echo " 部署完成 ✅   Endpoint: https://${HOST}"
echo "   健康檢查:   curl https://${HOST}/health"
echo "======================================================================"
