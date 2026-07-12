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

## 一鍵部署

```bash
AWS_PROFILE=dev ./deploy.sh
```

`deploy.sh` 依序做:venv → `cdk bootstrap` → 建 service-linked roles → deploy Network/Data →
填 app 密鑰 → build+push 映像(podman/docker)→ deploy ECS Express → 強制滾動 → 印出 endpoint。
全部步驟**冪等**,可重複執行。

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
