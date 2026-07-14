#!/usr/bin/env bash
#
# StockMood — 一鍵部署到 AWS(us-east-1)。
#
# 把「純 cdk deploy 之外」的手動前置全部串起來,讓乾淨帳號也能一次到位:
#   bootstrap → SLR → deploy Network/Data → 填密鑰 → SNS APNs Platform App → build+push 映像 → deploy ECS Express
#
# 用法:
#   AWS_PROFILE=dev ./deploy.sh
#   (或)  ./deploy.sh dev
#
# iOS 推播(SNS APNs Platform Application)會自動處理:
#   - repo 內 docs/AuthKey_*.p8 存在 → 自動建立/更新 APNS_SANDBOX + APNS 平台應用
#   - 也可用 APNS_SIGNING_KEY_PATH / APNS_KEY_ID / APNS_TEAM_ID / APNS_BUNDLE_ID 覆寫
#   - 平台應用已存在時直接沿用,不需要憑證
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
SNS_APNS_SANDBOX_ARN="${SNS_APNS_SANDBOX_ARN:-}"
SNS_APNS_ARN="${SNS_APNS_ARN:-}"
# APNs 憑證(token-based auth,.p8 對 sandbox/production 通用)。
# 第一次建立 Platform Application 時需要;之後 SNS 上已有就不再需要。
APNS_SIGNING_KEY_PATH="${APNS_SIGNING_KEY_PATH:-}"   # AuthKey_XXXXXXXXXX.p8 路徑
APNS_KEY_ID="${APNS_KEY_ID:-}"                       # Apple Developer 的 Key ID
APNS_TEAM_ID="${APNS_TEAM_ID:-8D8DJA42AA}"           # Apple Developer 的 Team ID
APNS_BUNDLE_ID="${APNS_BUNDLE_ID:-Wbilly.StockMoodApp}"
SNS_PLATFORM_APP_NAME="${SNS_PLATFORM_APP_NAME:-StockMood}"
BACKEND_DIR="$(cd "$(dirname "$0")/../backend" && pwd)"
INFRA_DIR="$(cd "$(dirname "$0")" && pwd)"

# 未指定 .p8 時,自動使用 repo 內 docs/AuthKey_*.p8(hackathon POC 便利措施;
# Key ID 直接取自檔名)。正式專案應改放 Secrets Manager,不要 commit 進 repo。
if [ -z "$APNS_SIGNING_KEY_PATH" ]; then
  REPO_P8="$(ls "$INFRA_DIR"/../docs/AuthKey_*.p8 2>/dev/null | head -1 || true)"
  if [ -n "$REPO_P8" ]; then
    APNS_SIGNING_KEY_PATH="$REPO_P8"
    P8_NAME="$(basename "$REPO_P8")"
    APNS_KEY_ID="${APNS_KEY_ID:-${P8_NAME#AuthKey_}}"
    APNS_KEY_ID="${APNS_KEY_ID%.p8}"
  fi
fi

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

echo "==> [1/9] Python venv + CDK deps"
if [ ! -d "$INFRA_DIR/.venv" ]; then python -m venv "$INFRA_DIR/.venv"; fi
"$INFRA_DIR/.venv/Scripts/python.exe" -m pip install -q -r "$INFRA_DIR/requirements.txt" 2>/dev/null \
  || "$INFRA_DIR/.venv/bin/python" -m pip install -q -r "$INFRA_DIR/requirements.txt"

echo "==> [2/9] CDK bootstrap(一次性,已 bootstrap 會直接略過)"
cdk bootstrap "aws://${ACCOUNT_ID}/${REGION}" >/dev/null

echo "==> [3/9] Service-linked roles(已存在則忽略)"
aws iam create-service-linked-role --aws-service-name ecs.amazonaws.com >/dev/null 2>&1 || true
aws iam create-service-linked-role --aws-service-name ecs.application-autoscaling.amazonaws.com >/dev/null 2>&1 || true

echo "==> [4/9] Deploy Network + Data(先要有 ECR 才能推映像)"
cdk deploy StockMood-Network StockMood-Data --require-approval never >/dev/null

echo "==> [5/9] 填 app 密鑰(缺 key 才補;OPENAI 先留空 → 走規則式 fallback)"
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

echo "==> [6/9] SNS APNs Platform Application(冪等:已存在則沿用)"
# CloudFormation 不支援 AWS::SNS::PlatformApplication,只能走 CLI。
# 建立需要 Apple 的 .p8 簽署金鑰(token-based auth,sandbox/production 共用);
# 平台應用一旦存在,之後部署不帶 APNS_* 也會自動撈到 ARN 沿用。
find_platform_app() {  # $1=platform(APNS|APNS_SANDBOX)
  aws sns list-platform-applications \
    --query "PlatformApplications[?ends_with(PlatformApplicationArn, ':app/$1/$SNS_PLATFORM_APP_NAME')].PlatformApplicationArn | [0]" \
    --output text | grep -v '^None$' || true
}

ensure_platform_app() {  # $1=platform → stdout: ARN(或空)
  local platform="$1" arn attrs_json
  arn="$(find_platform_app "$platform")"
  if [ -n "$APNS_SIGNING_KEY_PATH" ]; then
    # .p8 內容含換行,交給 python 組成單行 JSON 再整串傳給 CLI,
    # 避免 file:// 在 Git Bash / MSYS 路徑轉換下踩雷。
    attrs_json="$(python - "$APNS_SIGNING_KEY_PATH" "$APNS_KEY_ID" "$APNS_TEAM_ID" "$APNS_BUNDLE_ID" <<'PY'
import json, sys
key_path, key_id, team_id, bundle_id = sys.argv[1:5]
print(json.dumps({
    "PlatformCredential": open(key_path, encoding="utf-8").read(),
    "PlatformPrincipal": key_id,
    "ApplePlatformTeamID": team_id,
    "ApplePlatformBundleID": bundle_id,
}))
PY
)"
    if [ -n "$arn" ]; then
      aws sns set-platform-application-attributes \
        --platform-application-arn "$arn" --attributes "$attrs_json" >&2
      echo "    -> $platform 已存在,更新 APNs 憑證" >&2
    else
      arn="$(aws sns create-platform-application --name "$SNS_PLATFORM_APP_NAME" \
        --platform "$platform" --attributes "$attrs_json" \
        --query PlatformApplicationArn --output text)"
      echo "    -> $platform 已建立" >&2
    fi
  elif [ -n "$arn" ]; then
    echo "    -> $platform 已存在,沿用" >&2
  fi
  echo "$arn"
}

if [ -n "$APNS_SIGNING_KEY_PATH" ]; then
  [ -f "$APNS_SIGNING_KEY_PATH" ] || { echo "ERROR: 找不到 .p8:$APNS_SIGNING_KEY_PATH"; exit 1; }
  [ -n "$APNS_KEY_ID" ] && [ -n "$APNS_TEAM_ID" ] \
    || { echo "ERROR: 帶 APNS_SIGNING_KEY_PATH 時,APNS_KEY_ID 與 APNS_TEAM_ID 必填"; exit 1; }
fi
if [ -z "$SNS_APNS_SANDBOX_ARN" ]; then SNS_APNS_SANDBOX_ARN="$(ensure_platform_app APNS_SANDBOX)"; fi
if [ -z "$SNS_APNS_ARN" ]; then SNS_APNS_ARN="$(ensure_platform_app APNS)"; fi
if [ -z "$SNS_APNS_SANDBOX_ARN" ] && [ -z "$SNS_APNS_ARN" ]; then
  echo "    -> 未提供 APNs 憑證且 SNS 上也沒有既有 Platform Application,略過"
  echo "       (推播註冊 API 仍可用,狀態會是 pending_sns_configuration;"
  echo "        之後帶 APNS_SIGNING_KEY_PATH/APNS_KEY_ID/APNS_TEAM_ID 重跑即可補上)"
fi

SNS_CONTEXT_ARGS=()
if [ -n "$SNS_APNS_SANDBOX_ARN" ]; then
  SNS_CONTEXT_ARGS+=( -c "sns_apns_sandbox_arn=$SNS_APNS_SANDBOX_ARN" )
  echo "    -> sandbox ARN: $SNS_APNS_SANDBOX_ARN"
fi
if [ -n "$SNS_APNS_ARN" ]; then
  SNS_CONTEXT_ARGS+=( -c "sns_apns_arn=$SNS_APNS_ARN" )
  echo "    -> production ARN: $SNS_APNS_ARN"
fi

echo "==> [7/9] Build + push 映像($CONTAINER, linux/amd64)"
aws ecr get-login-password | "$CONTAINER" login --username AWS --password-stdin "${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"
"$CONTAINER" build --platform linux/amd64 -t "${ECR_URI}:${IMAGE_TAG}" "$BACKEND_DIR"
"$CONTAINER" push "${ECR_URI}:${IMAGE_TAG}"

echo "==> [8/9] Deploy ECS Express"
cdk deploy StockMood-EcsExpress --require-approval never "${SNS_CONTEXT_ARGS[@]}" >/dev/null

echo "==> [9/9] 強制滾動最新映像(cdk 對同 tag 不會偵測變更)"
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
