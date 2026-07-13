# AgentCore

StockMood 的 Bedrock AgentCore 服務——獨立於 `AwsStockApp` 的 git repo，不與後端程式碼混放。

第一個能力：**庫存分析洞察 agent**（`PortfolioInsight`），疊加在 `AwsStockApp` 後端既有的規則式庫存分析結果之上，透過 AgentCore Gateway 的 4 個工具（持股/大盤為真實後端 API、新聞/籌碼暫為 mock）產生更豐富的洞察文字。

- 設計文件：[`docs/superpowers/specs/`](docs/superpowers/specs/)
- 實作計畫：[`docs/superpowers/plans/`](docs/superpowers/plans/)

## 架構速覽

```
invoke ──> AgentCore Runtime(PortfolioInsight, Strands + sonnet-4-5)
              │  SigV4 MCP(mcp-proxy-for-aws)
              ▼
           AgentCore Gateway(AWS_IAM auth)
              │  4 個 Lambda targets
              ▼
   get_portfolio_holdings / get_market_compare ──> StockMood 後端(真實 API, X-User-Id)
   get_latest_news / get_chip_data              ──> mock(契約已鎖定)
```

- Gateway + Lambda + IAM + SSM:CDK(Python)於 [`infra/`](infra/),tag `Project=StockMood-Hackathon`。
- Runtime:AgentCore CLI(`@aws/agentcore`)於 [`PortfolioInsight/`](PortfolioInsight/),CodeZip 免容器。
- Gateway URL 由 CDK 寫入 SSM `/stockmood/agentcore/gateway-url`,agent 冷啟動讀取。

## 部署順序(從零到可 invoke,2026-07-13 實測通過)

前置:
- Node 20+、`npm install -g @aws/agentcore`、**`uv` 需在 PATH**(`pip install uv` 後確認 `uv --version`)
- Python 3.11+;repo root `python -m venv .venv && pip install -r requirements-dev.txt mcp-proxy-for-aws`
- AWS profile `dev`(us-east-1、帳號已 `cdk bootstrap`,AwsStockApp Phase 1 已做過)
- Bedrock 可用 `us.anthropic.claude-sonnet-4-5-20250929-v1:0`(**別用 haiku-4-5**,本帳號會 AccessDenied)

```bash
# 0. 確認後端現行 URL(ECS Express 每次重部署會換網域!)
curl -s -o /dev/null -w "%{http_code}" $BACKEND_BASE_URL/health   # 要 200

# 1. Gateway + Lambda tools(CDK)
BACKEND_BASE_URL=https://<現行後端網域> AWS_PROFILE=dev ./scripts/deploy_gateway.sh

# 2. Gateway 煙霧測試(SigV4 MCP:列 4 工具 + 實呼叫 holdings)
AWS_PROFILE=dev python scripts/gateway_smoke.py --user-id demo-user   # 期望 SMOKE OK

# 3. Agent Runtime(AgentCore CLI 部署 + runtime 角色補權限)
AWS_PROFILE=dev ./scripts/deploy_runtime.sh

# 4. 雲端 invoke 驗證
AWS_PROFILE=dev python scripts/invoke_test.py --user-id demo-user     # 期望 INVOKE OK
```

清除:`AWS_PROFILE=dev ./scripts/destroy.sh`(之後 `git checkout -- PortfolioInsight/agentcore/` 還原被 remove all 改寫的設定檔)。

後端換網域後:只需重跑步驟 1(帶新 URL)——只更新 Lambda env,Gateway URL 不變,Runtime 不用動。

## 開發

```bash
# 單元測試(Lambda tools)
python -m pytest tests -v
# CDK synth 斷言測試
cd infra && python -m pytest tests -v
# 本機跑 agent(打真 Gateway)
cd PortfolioInsight && AWS_PROFILE=dev agentcore dev
curl -s -X POST http://localhost:8080/invocations -H "Content-Type: application/json" -d '{"user_id":"demo-user"}'
```

## 踩坑備忘(Windows / Git Bash)

- SSM 參數名 `/stockmood/...` 開頭斜線會被 Git Bash 轉成本機路徑:單條指令前綴 `MSYS_NO_PATHCONV=1`,**不要**設全域。
- `agentcore dev` 停掉背景工作後 uvicorn 子程序可能殘留佔 8080:`netstat -ano | grep :8080` 找 PID 後 `taskkill //PID <pid> //F //T`。
- 改 agent 的 pyproject 依賴後要在 `PortfolioInsight/app/PortfolioInsight` 跑 `uv lock && uv sync`,dev server 不會自動補裝。
- `aws-targets.json` 的 target 名必須是 `default`(CLI 預設找這個名字)。
- CloudFormation 會截斷 IAM 角色名(實測 `AgentCore-PortfolioInsigh-...` 少一個 t),腳本查角色用短字串。
