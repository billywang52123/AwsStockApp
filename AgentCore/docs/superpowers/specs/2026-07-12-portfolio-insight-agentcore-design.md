# 庫存分析洞察 Agent — AgentCore 框架設計

- **日期:** 2026-07-12
- **專案:** 2026 黑客松 AWS × 國泰 — StockMood 後端上雲的 AgentCore 階段
- **標的:** 全新獨立 repo `AgentCore`(與 `AwsStockApp` 分開,不混放程式碼/infra)
- **目標:** 把 Bedrock AgentCore 的 Runtime + Gateway + Tool 框架搭出來並跑通,第一個實際串接的能力是「庫存分析」洞察生成。

**與既有整體遷移設計的關係:** 本文是 [`AwsStockApp` 遷移設計文件](../../../../docs/superpowers/specs/2026-07-11-aws-backend-cloud-migration-design.md) 中「遷移步驟 5/6:AgentCore Agent A / B」的細部設計,範圍聚焦在原設計 Agent B(投組洞察)所涵蓋的「庫存分析」子集,且改採獨立 repo。找股(Agent A)、卡片、運勢、Cognito 不在本階段範圍。

---

## 1. 現況(Baseline)

`AwsStockApp/backend` 的 `/api/portfolio/analysis`(`PortfolioAnalysisService`)是**純規則式計算**,不吃任何 LLM:市值、風險分數、產業曝險、持股明細、風險提醒(`risk_notices`)全部由 `portfolio_analysis_service.py` 的固定公式產生安撫語氣文字。`/api/market/compare` 提供個人化的大盤比較資料,同樣是規則式。兩者皆已部署在雲端,對外有公開 HTTPS endpoint,且接受 legacy 的 `X-User-Id` header 免登入呼叫(`ALLOW_LEGACY_HEADER_AUTH`)。

「最新資訊」「籌碼」兩類資料後端完全沒有對應資料源。

---

## 2. 目標與範圍

**做什麼:** 建一個 Strands agent(`portfolio_insight_agent`),疊加在既有規則式庫存分析結果之上,呼叫工具取得數字與脈絡,產生更豐富的洞察文字/逐檔短評——**不取代**現有規則式數字計算。

**這階段明確不做(YAGNI):**
- 不接回 `AwsStockApp` 後端(不修改 `/portfolio/analysis` 或新增呼叫 agent 的程式碼);本階段成果以 CLI/腳本手動 invoke 驗證即可。
- 不做找股 Agent A。
- 不做卡片、運勢 agent 化。
- 不做 Cognito / 真實登入。
- 不做真實新聞或籌碼資料源(維持 mock)。
- 不做 CI/CD。

---

## 3. 架構

```
AgentCore/                       (獨立 git repo,獨立於 AwsStockApp)
├── PortfolioInsight/            Strands agent 專案(由 AgentCore CLI `agentcore create` 產生)
│   ├── agentcore/               CLI 設定(agentcore.json / aws-targets.json)
│   └── app/PortfolioInsight/main.py   agent 入口
├── tools/                       Gateway target 用的 Lambda handler(4 個)
│   ├── get_portfolio_holdings.py
│   ├── get_market_compare.py
│   ├── get_latest_news.py       (mock)
│   └── get_chip_data.py         (mock)
├── infra/                       CDK(Python)— Gateway + Lambda + IAM
├── scripts/
│   ├── deploy_runtime.sh        agentcore configure + launch
│   ├── deploy_gateway.sh        cdk deploy
│   ├── destroy.sh
│   └── invoke_test.py           手動驗證用:boto3 invoke_agent_runtime
├── tests/
│   ├── tools/                   4 個 Lambda 的 unit test
│   └── infra/                   CDK synth 斷言測試
└── docs/superpowers/{specs,plans}/
```

**部署分工(方案 A,2026-07-12 查證修正):**
- **Runtime**(agent 本體):用官方 **AgentCore CLI**(npm 套件 `@aws/agentcore`;`agentcore create` / `dev` / `deploy` / `invoke`)。原定的 `bedrock-agentcore-starter-toolkit` 已標 legacy,官方明示新專案改用 AgentCore CLI。新 CLI 底層自己走 CDK/CloudFormation,預設 CodeZip 打包(**不需容器**,免 podman)。
- **Gateway + 4 個 Lambda tool + IAM role**:用 CDK(Python),放在 `infra/`,比照 `AwsStockApp/infra` 的既有慣例——`Tags.of(app)` 套用 `Project=StockMood-Hackathon` / `Environment=hackathon` / `ManagedBy=CDK`,可重複部署與用 Tag Editor 清除。Gateway 的 CDK 支援已進 stable(`aws-cdk-lib.aws_bedrockagentcore` 的 `CfnGateway` / `CfnGatewayTarget`)。

**Gateway 認證:** 用 `AuthorizerType=AWS_IAM`(SigV4)——CloudFormation 已支援,不必為了 Gateway 先架 Cognito/OAuth。呼叫端(agent 與本機測試腳本)以 `mcp-proxy-for-aws` 套件的 `aws_iam_streamablehttp_client` 對 Gateway endpoint 做 SigV4 簽章。

**Agent 如何拿到工具:** Runtime 啟動時,agent 透過 MCP 協定(SigV4)連上已部署的 Gateway endpoint,發現並呼叫 4 個工具——這是 AgentCore 的標準模式(Gateway 把 Lambda 轉成 MCP tool)。Gateway URL 由 infra stack 寫進 SSM Parameter Store,agent 冷啟動時讀取(避免跨部署工具手動搬 URL)。

**區域與帳號:** 沿用既有慣例,us-east-1、同一 hackathon AWS 帳號。

---

## 4. Agent 設計

- **名稱:** `portfolio_insight_agent`(對應原整體設計 Agent B,範圍縮小為庫存分析)
- **框架:** Strands Agents SDK
- **模型:** 預設用 `us.anthropic.claude-sonnet-4-5-20250929-v1:0`(帳號已驗證可用;`claude-haiku-4-5` 在本帳號會回 `AccessDeniedException`,是 Marketplace 訂閱狀態問題,別選這支)。可用環境變數覆寫。部署前若又遇到 Bedrock `AccessDeniedException`,先用 `dev` profile 直接 boto3 `converse` 測試該模型,判斷是帳號訂閱問題還是 IAM 問題。
- **System prompt 規則:**(延續現有規則式文字的語氣與限制,見 `portfolio_analysis_service.py` 既有文案)
  - 繁體中文、安撫語氣。
  - **禁止**出現具體買賣建議或明確的「該買/該賣」字眼。
  - 基於工具回傳的實際數字說話,不得捏造未提供的數字。
  - 產出精簡:整體洞察一段 + 每檔持股(依權重排序,最多前 5 檔)一句話短評。
- **輸入:** `{"user_id": "<string>"}`
- **輸出(結構化 JSON):**
  ```json
  {
    "insight_summary": "整體洞察文字…",
    "holding_notes": [
      {"symbol": "2330", "note": "一句話短評…"}
    ]
  }
  ```
- **工具呼叫策略:** 一定呼叫 `get_portfolio_holdings`(取得規則式數字與 risk_notices 當推理基礎);是否呼叫 `get_market_compare` / `get_latest_news` / `get_chip_data` 由 agent 自行依推理需要決定(不強制全呼叫,避免不必要的延遲)。

---

## 5. 工具(Gateway Targets)

| 工具 | 資料源 | 說明 |
|---|---|---|
| `get_portfolio_holdings(user_id)` | 真實後端 `GET /api/portfolio/analysis`(header `X-User-Id`) | 回傳市值、風險分數、產業曝險、持股明細、風險提醒 |
| `get_market_compare(user_id)` | 真實後端 `GET /api/market/compare`(header `X-User-Id`) | 個人化大盤比較 |
| `get_latest_news(symbols)` | mock | 回固定中性新聞樣板,依產業關鍵字挑選模板 |
| `get_chip_data(symbols)` | mock | 回固定法人買賣超樣板數字 |

每個工具是一個 Lambda,由 Gateway 以 MCP tool 形式暴露給 agent。後端 base URL 以 Lambda 環境變數注入,不寫死在程式碼——目前是 `https://st-2f8caae5711f455a9318dbe4a15ec9a2.ecs.us-east-1.on.aws`,但 **ECS Express 每次重新部署都會換一個新網域**,故此值只在 CDK 部署時當參數傳入(如 `.env` 或 CDK context),部署前務必先確認後端當下的實際 endpoint,不可假設不變。

---

## 6. 資料流(本階段,獨立驗證)

1. 開發者執行 `scripts/invoke_test.py --user-id demo-user`。
2. boto3 呼叫 AgentCore Runtime 的 `invoke_agent_runtime`。
3. `portfolio_insight_agent` 推理,透過 MCP 連上 Gateway,呼叫 `get_portfolio_holdings`(必呼叫)取得真實規則式數字,視需要再呼叫其他工具。
4. Agent 產生符合語氣規則的結構化洞察 JSON。
5. Runtime 回傳結果,腳本印出供人工檢視是否合理、語氣是否正確、有無捏造數字。

---

## 7. 錯誤處理

- **Lambda tool 呼叫後端逾時/5xx:** 不 raise,回傳結構化的 `{"error": "..."}` 給 agent,讓 agent 能講「資料暫時取不到,先看基本數字就好」而不是整個失敗。逾時設短(5 秒),後端本身已是常駐雲端服務。
- **Agent 端全工具失敗:** 有安全的 fallback 文字(語氣同既有規則式 fallback),絕不回空白或例外訊息給呼叫端。
- **認證:** 工具呼叫後端一律用 `X-User-Id` legacy header;本階段不處理真實 JWT/Cognito(後端本身就還在過渡期接受 legacy header)。

---

## 8. 測試策略

- **4 個 Lambda tool:** unit test,mock 對後端的 HTTP 呼叫,驗證 request 組法(header、URL)與 response 映射,以及逾時/錯誤路徑回傳結構化錯誤。
- **CDK infra:** synth 斷言測試,比照 `AwsStockApp/infra` 既有測試慣例(驗 Gateway/Lambda/IAM 資源存在、tag 正確)。
- **Agent 推理本身:** LLM 輸出不可斷言，不寫死 assertion；用 `invoke_test.py` 人工驗證輸出語氣、有無捏造數字、有無出現買賣建議字眼。

---

## 9. 風險與注意事項

- **AgentCore 新服務學習曲線:** Runtime/Gateway 部署路徑(toolkit CLI + CDK 混用)是新嘗試,預留除錯時間。
- **MCP 連線設定:** Agent 執行環境需要正確的 Gateway endpoint 與授權設定,首次跑通前預期會有幾輪除錯。
- **Prompt 紀律:** 務必保留「不得出現買賣建議」與「不得捏造數字」的限制,即使 agent 有更大的敘事自由度。
- **成本:** Bedrock 模型呼叫 + AgentCore Runtime/Gateway 皆按量計費,黑客松規模可控;閒置時記得 `destroy.sh` 清除。

---

## 10. 版本控制

`AgentCore` 為獨立 git repo(`git init` 於本目錄),與 `AwsStockApp` 完全分開。實作改動走 feature branch,不直接改 `main`。
