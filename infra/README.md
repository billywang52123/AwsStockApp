# StockMood 基礎建設(AWS CDK, us-east-1)

Phase 1 上雲:核心 FastAPI 跑在 **Amazon ECS Express Mode**(App Runner 2026 接班人),
搭 **RDS PostgreSQL**、**ECR**、**Secrets Manager**;OCR 對帳單走 **Bedrock Vision**。
所有資源自動帶 tag `Project=StockMood-Hackathon` / `Environment=hackathon` / `ManagedBy=CDK`。

## Stacks

| Stack | 內容 |
|---|---|
| `StockMood-Network` | VPC(public / app / db 三層子網)、RDS SG、ECS service SG |
| `StockMood-Data` | RDS PostgreSQL 16(私有)、app 密鑰、ECR repo |
| `StockMood-EcsExpress` | `CfnExpressGatewayService` + infra/execution/task 三角色(task role → Bedrock + 讀 DB 密鑰),放 public 子網 → internet-facing ALB |
| `StockMood-Notifications` | VPC Lambda Container + Secrets Manager/Bedrock Runtime/SNS Interface Endpoints + DynamoDB 防重 + 每日 EventBridge Scheduler(預設停用) |

## 一鍵部署

```bash
AWS_PROFILE=dev ./deploy.sh
```

### iOS 推播(SNS APNs)

CloudFormation 不支援 `AWS::SNS::PlatformApplication`，因此由 `deploy.sh` 以 CLI
建立/維護 `APNS_SANDBOX` 與 `APNS` 兩個 Platform Application（名稱 `StockMood`，
token-based auth，同一把 `.p8` 通用），並把 ARN 經 CDK context 注入
ECS 的 IAM 權限與環境變數：

- repo 內有 `docs/AuthKey_*.p8` 時自動使用（Key ID 取自檔名；Team ID 預設 `8D8DJA42AA`）
- 可用 `APNS_SIGNING_KEY_PATH` / `APNS_KEY_ID` / `APNS_TEAM_ID` / `APNS_BUNDLE_ID`
  （預設 `Wbilly.StockMoodApp`）覆寫
- Platform Application 已存在時自動撈 ARN 沿用；也可直接以
  `SNS_APNS_SANDBOX_ARN` / `SNS_APNS_ARN` 指定略過偵測

未設定 SNS 時，`POST /api/push-devices` 仍會先將 APNs device token
綁定登入使用者並存入 RDS，狀態為 `pending_sns_configuration`；SNS 就緒後重新註冊，
後端會建立 SNS EndpointArn，狀態改為 `active`。

### 個人化持股推播 Lambda

`StockMood-Notifications` 會從 `public.portfolio_items`、`public.push_devices` 與
`raw.raw_01_price_valuation_2025` 選出指定日期波動最大的持股，使用 Bedrock Converse
產生繁體中文文案（失敗時走安全模板），再由 SNS/APNs 發送。真實日期會保留月日並映射到
2025；也可在 invoke payload 明確指定 `demo_date`。

部署後先以單一使用者 dry-run 驗證，這不會發送 SNS：

```bash
aws lambda invoke --function-name stockmood-personalized-push \
  --cli-binary-format raw-in-base64-out \
  --payload '{"demo_date":"2025-07-14","user_id":"<user-id>","dry_run":true}' \
  notification-response.json
```

確認回傳 candidate/content 後，再將 `dry_run` 改成 `false` 做實機推播。每日 14:30
(`Asia/Taipei`) 的 EventBridge Scheduler **預設為 DISABLED**；完整串測成功後才啟用：

```bash
cd infra
npx aws-cdk@latest deploy StockMood-Notifications \
  -c notification_schedule_enabled=true --require-approval never
```

Scheduler 會以 `all_users=true`、`dry_run=false` 執行。Lambda 預設 reserved concurrency 為 1，
且未指定 `user_id` 或明確 `all_users=true` 時會拒絕執行，避免誤發。

`deploy.sh` 依序做:venv → `cdk bootstrap` → 建 service-linked roles → deploy Network/Data →
填 app 密鑰 → SNS APNs Platform Application → build+push 映像(podman/docker)→
deploy ECS Express → 強制滾動 → 印出 endpoint。全部步驟**冪等**,可重複執行。

## 前置需求

- AWS CLI 設好該 profile 憑證
- Node.js(cdk CLI 透過 `npx` 取得)、Python 3.11+、podman 或 docker
- Bedrock:us-east-1 需開通所用視覺模型存取(本專案用 `us.anthropic.claude-haiku-4-5-20251001-v1:0`)

## 改後端程式後重新部署

`cdk deploy` 對同一個 `:latest` tag **不會**偵測到變更,故 `deploy.sh` 最後會 `--force-new-deployment`。
只想更新程式(基建沒動)可單獨跑:

```bash
export MSYS_NO_PATHCONV=1
aws ecr get-login-password --profile dev | podman login --username AWS --password-stdin <acct>.dkr.ecr.us-east-1.amazonaws.com
podman build --platform linux/amd64 -t <acct>.dkr.ecr.us-east-1.amazonaws.com/stockmood-api:latest ../backend
podman push <acct>.dkr.ecr.us-east-1.amazonaws.com/stockmood-api:latest
aws ecs update-service --cluster default --service stockmood-api --force-new-deployment --profile dev --region us-east-1
```

## 密鑰

- `stockmood/db` — RDS 自動產生(user/pass/host/dbname);app 用 `DB_SECRET_ARN` runtime 取得。
- `stockmood/app` — `OPENAI_API_KEY`(留空 → 分析/卡片/運勢/找股走規則式 fallback)、`JWT_SECRET`、`ADMIN_API_KEY`。
  要用真的 OpenAI:更新此密鑰的 `OPENAI_API_KEY` 後 `--force-new-deployment`。

## 清理

```bash
AWS_PROFILE=dev ./destroy.sh
```

## 已知環境相依

- `cdk.json` 的 app 指令是 **Windows 路徑**(`.venv\Scripts\python.exe app.py`)。
  在 Linux/mac 執行請改成 `.venv/bin/python app.py`。
- Git Bash 需 `MSYS_NO_PATHCONV=1`(腳本已內建),否則 `/aws/...` 參數會被改寫成 Windows 路徑。

## 部署時踩過的坑(已在 code / 腳本處理)

1. SG 規則描述不能含 `>` 字元。
2. Infra 角色 policy 在 `service-role/` 路徑。
3. 需先建 Application Auto Scaling 的 service-linked role(deploy.sh 步驟 3)。
4. ALB 對外與否由子網型別決定 → 放 public 子網。
5. 改子網會觸發 cross-stack 匯出衝突 → 先 `delete-stack StockMood-EcsExpress` 再 deploy。
6. ECS Express 部署 circuit breaker 綁 `RollbackAlarm`(5xx):部署期間別對舊服務打出 500,否則自動回滾。
7. Bedrock 模型會 EOL(`ResourceNotFoundException: end of life`)→ 換當時可用的視覺模型 ID。
