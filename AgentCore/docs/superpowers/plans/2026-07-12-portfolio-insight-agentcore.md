# 庫存分析洞察 Agent(AgentCore)Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在獨立 repo `AgentCore` 建出可部署、可 invoke 的 Bedrock AgentCore 框架:Gateway(4 個 Lambda tool)+ Runtime(Strands agent `portfolio_insight_agent`),疊加在後端既有規則式庫存分析之上生成洞察文字。

**Architecture:** Gateway + 4 Lambda + IAM 用 CDK(Python)管理(`infra/`,AWS_IAM inbound auth);agent 用官方 AgentCore CLI(`@aws/agentcore`,CodeZip,免容器)scaffold 與部署;agent 經 `mcp-proxy-for-aws` 以 SigV4 連 Gateway MCP endpoint;Gateway URL 由 infra stack 寫入 SSM Parameter,agent 冷啟動讀取。

**Tech Stack:** Python 3.11+(Lambda 3.13 runtime, stdlib-only)、AWS CDK v2(Python)、Strands Agents SDK、`bedrock-agentcore`、`mcp-proxy-for-aws`、AgentCore CLI(Node 20+ npm 套件)、pytest。

**Spec:** [`docs/superpowers/specs/2026-07-12-portfolio-insight-agentcore-design.md`](../specs/2026-07-12-portfolio-insight-agentcore-design.md)

## Global Constraints

- **區域:** 一律 `us-east-1`;AWS profile `dev`(帳號 475794918554)。AgentCore CLI 預設 us-west-2,`agentcore/aws-targets.json` 務必改成 us-east-1。
- **Tag:** CDK app 全域 `Project=StockMood-Hackathon` / `Environment=hackathon` / `ManagedBy=CDK`(比照 `AwsStockApp/infra/app.py`)。
- **模型:** `us.anthropic.claude-sonnet-4-5-20250929-v1:0`。**不可用 `claude-haiku-4-5`**(本帳號 Marketplace 訂閱問題會回 AccessDeniedException)。遇 Bedrock AccessDenied 先用 dev profile 直接 boto3 `converse` 測該模型分辨訂閱/IAM 問題。
- **後端 base URL 不寫死:** 部署時以環境變數 `BACKEND_BASE_URL` 傳入(ECS Express 每次重部署換網域)。目前值:`https://st-2f8caae5711f455a9318dbe4a15ec9a2.ecs.us-east-1.on.aws`,用前要跟使用者確認仍有效。
- **文案硬限制:** agent 輸出繁體中文、安撫語氣;**禁止**具體買賣建議字眼;**不得捏造**工具未提供的數字。
- **版控:** 實作在 `feature/portfolio-insight-agent` 分支,不直接改 `main`。頻繁 commit。
- **Windows 環境:** Git Bash 跑 shell 腳本;**不要**全域 `export MSYS_NO_PATHCONV=1`(會壞 pip/npm 本機路徑),只在查 `/aws/...` log group 的單一指令前綴使用。
- **本計畫所有 pytest 從 repo root 跑**,`python -m pytest`(確保 rootdir 一致)。

---

### Task 1: Repo 腳手架與開發環境

**Files:**
- Create: `.gitignore`
- Create: `requirements-dev.txt`
- Create: `pytest.ini`

**Interfaces:**
- Produces: feature 分支、可跑 pytest 的環境;後續所有 task 在此分支上工作。

- [ ] **Step 1: 建立 feature 分支**

```bash
cd "D:/國泰/01_2026黑客松_AWSxCmoney/AgentCore"
git checkout -b feature/portfolio-insight-agent
```

- [ ] **Step 2: 寫 `.gitignore`**

```gitignore
__pycache__/
*.pyc
.venv/
venv/
.pytest_cache/
cdk.out/
node_modules/
.env
.env.local
*.egg-info/
```

- [ ] **Step 3: 寫 `requirements-dev.txt` 與 `pytest.ini`**

`requirements-dev.txt`:
```
pytest>=7.3.0
aws-cdk-lib>=2.220.0,<3.0.0
constructs>=10.0.0,<11.0.0
boto3>=1.34.0
```

`pytest.ini`:
```ini
[pytest]
testpaths = tests
```
(infra 的 CDK 測試獨立在 `infra/` 目錄下跑,比照 AwsStockApp 慣例,不進 root testpaths。)

- [ ] **Step 4: 建 venv 並安裝**

```bash
python -m venv .venv
source .venv/Scripts/activate
pip install -r requirements-dev.txt
python -m pytest --collect-only
```
Expected: `no tests ran`(收集成功、無錯誤)。

- [ ] **Step 5: 確認工具鏈前置(不裝在 repo,只驗證)**

```bash
node --version    # 需 v20+
npm --version
npx cdk --version # CDK v2
aws --profile dev sts get-caller-identity   # 帳號 475794918554
```
若 `agentcore` 未安裝:`npm install -g @aws/agentcore`,然後 `agentcore --help` 應列出 create/dev/deploy/invoke 等指令。任一前置失敗,停下回報使用者,不要繞路。

- [ ] **Step 6: Commit**

```bash
git add .gitignore requirements-dev.txt pytest.ini
git commit -m "chore: dev scaffolding (gitignore, dev deps, pytest config)"
```

---

### Task 2: 真實後端工具 Lambda — `get_portfolio_holdings` 與 `get_market_compare`

**Files:**
- Create: `tools/backend_client.py`(共用 HTTP helper)
- Create: `tools/get_portfolio_holdings.py`
- Create: `tools/get_market_compare.py`
- Test: `tests/tools/test_backend_tools.py`

**Interfaces:**
- Produces: `handler(event, context) -> dict`。event 是 Gateway 傳入的工具參數(如 `{"user_id": "demo-user"}`)。成功回後端 JSON 的 `data` 欄位;失敗回 `{"error": "<繁中說明>"}`(不 raise)。
- 環境變數:`BACKEND_BASE_URL`(必要)。
- `backend_client.get_json(path: str, user_id: str) -> dict`:對 `{BACKEND_BASE_URL}{path}` 發 GET,header `X-User-Id: {user_id}`,timeout 5 秒。

- [ ] **Step 1: 寫失敗測試**

Lambda 打包以 `tools/` 目錄為根,runtime 內是**平面模組**(`from backend_client import ...`),所以測試也把 `tools/` 加進 `sys.path` 用平面名稱 import/patch——跟 Lambda 內一致。

`tests/tools/test_backend_tools.py`:
```python
"""Gateway Lambda tools 的單元測試:mock urllib,不打真網路。"""
import io
import json
import sys
import urllib.error
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))

import pytest


@pytest.fixture(autouse=True)
def base_url(monkeypatch):
    monkeypatch.setenv("BACKEND_BASE_URL", "https://backend.example")


def _fake_response(payload: dict):
    body = io.BytesIO(json.dumps(payload).encode())
    body.status = 200
    body.__enter__ = lambda s: s
    body.__exit__ = lambda s, *a: False
    return body


def test_holdings_calls_backend_with_user_header(monkeypatch):
    captured = {}

    def fake_urlopen(req, timeout):
        captured["url"] = req.full_url
        captured["x_user_id"] = req.get_header("X-user-id")
        captured["timeout"] = timeout
        return _fake_response({"success": True, "data": {"risk_score": 55}})

    monkeypatch.setattr("backend_client.urllib.request.urlopen", fake_urlopen)
    from get_portfolio_holdings import handler

    result = handler({"user_id": "demo-user"}, None)

    assert result == {"risk_score": 55}
    assert captured["url"] == "https://backend.example/api/portfolio/analysis"
    assert captured["x_user_id"] == "demo-user"
    assert captured["timeout"] == 5


def test_market_compare_path(monkeypatch):
    def fake_urlopen(req, timeout):
        assert req.full_url == "https://backend.example/api/market/compare"
        return _fake_response({"success": True, "data": {"market_change": -0.4}})

    monkeypatch.setattr("backend_client.urllib.request.urlopen", fake_urlopen)
    from get_market_compare import handler

    assert handler({"user_id": "demo-user"}, None) == {"market_change": -0.4}


def test_missing_user_id_returns_error():
    from get_portfolio_holdings import handler
    result = handler({}, None)
    assert "error" in result


def test_backend_failure_returns_structured_error(monkeypatch):
    def fake_urlopen(req, timeout):
        raise urllib.error.URLError("timeout")

    monkeypatch.setattr("backend_client.urllib.request.urlopen", fake_urlopen)
    from get_portfolio_holdings import handler

    result = handler({"user_id": "demo-user"}, None)
    assert "error" in result and "暫時" in result["error"]
```

另建空的 `tests/__init__.py`、`tests/tools/__init__.py`。`tools/` 目錄**不放** `__init__.py`(它是 Lambda asset 根,保持平面)。

- [ ] **Step 2: 跑測試,確認失敗**

```bash
python -m pytest tests/tools -v
```
Expected: FAIL(`ModuleNotFoundError: tools.get_portfolio_holdings`)。

- [ ] **Step 3: 實作**

`tools/backend_client.py`:
```python
"""呼叫 StockMood 後端的共用 helper。stdlib-only,Lambda 免打包依賴。"""
import json
import os
import urllib.request

TIMEOUT_SECONDS = 5


def get_json(path: str, user_id: str) -> dict:
    base_url = os.environ["BACKEND_BASE_URL"].rstrip("/")
    req = urllib.request.Request(
        f"{base_url}{path}",
        headers={"X-User-Id": user_id, "Accept": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=TIMEOUT_SECONDS) as resp:
        return json.loads(resp.read().decode())


UNAVAILABLE_MSG = "資料暫時取不到,請先以既有的基本數字說明,不要編造數值。"


def call_backend_tool(path: str, event: dict) -> dict:
    user_id = (event or {}).get("user_id", "").strip()
    if not user_id:
        return {"error": "缺少 user_id 參數。"}
    try:
        body = get_json(path, user_id)
    except Exception:  # noqa: BLE001 — 對 agent 一律回結構化錯誤,不讓 Lambda 炸掉
        return {"error": UNAVAILABLE_MSG}
    if not body.get("success"):
        return {"error": UNAVAILABLE_MSG}
    return body.get("data", {})
```

`tools/get_portfolio_holdings.py`:
```python
"""Gateway tool:讀後端規則式庫存分析(市值/風險分數/產業曝險/持股/風險提醒)。"""
from backend_client import call_backend_tool  # Lambda 打包後是平面模組


def handler(event, context):
    return call_backend_tool("/api/portfolio/analysis", event)
```

`tools/get_market_compare.py`:
```python
"""Gateway tool:讀後端個人化大盤比較。"""
from backend_client import call_backend_tool


def handler(event, context):
    return call_backend_tool("/api/market/compare", event)
```

- [ ] **Step 4: 跑測試,確認通過**

```bash
python -m pytest tests/tools -v
```
Expected: 4 PASS。

- [ ] **Step 5: Commit**

```bash
git add tools/ tests/
git commit -m "feat: backend-backed gateway tools (holdings, market compare)"
```

---

### Task 3: Mock 工具 Lambda — `get_latest_news` 與 `get_chip_data`

**Files:**
- Create: `tools/get_latest_news.py`
- Create: `tools/get_chip_data.py`
- Test: `tests/tools/test_mock_tools.py`

**Interfaces:**
- Produces: `handler(event, context) -> dict`。event `{"symbols": ["2330", ...]}`。回傳固定 mock 內容,**每筆都帶 `"is_mock": True`**,讓 agent prompt 能提示「此為示意資料」。契約先鎖定,之後換真資料源不改上層。

- [ ] **Step 1: 寫失敗測試**

`tests/tools/test_mock_tools.py`:
```python
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))


def test_news_returns_one_item_per_symbol():
    from get_latest_news import handler
    result = handler({"symbols": ["2330", "2317"]}, None)
    assert result["is_mock"] is True
    assert [n["symbol"] for n in result["news"]] == ["2330", "2317"]
    assert all(n["headline"] for n in result["news"])


def test_news_empty_symbols():
    from get_latest_news import handler
    assert handler({"symbols": []}, None)["news"] == []


def test_chip_data_shape():
    from get_chip_data import handler
    result = handler({"symbols": ["2330"]}, None)
    assert result["is_mock"] is True
    item = result["chips"][0]
    assert item["symbol"] == "2330"
    assert set(item) >= {"symbol", "foreign_net_buy_lots", "trust_net_buy_lots", "note"}
```

- [ ] **Step 2: 跑測試,確認失敗**

```bash
python -m pytest tests/tools/test_mock_tools.py -v
```
Expected: FAIL(module not found)。

- [ ] **Step 3: 實作**

`tools/get_latest_news.py`:
```python
"""Gateway tool(mock):固定中性新聞樣板。真資料源到位後只換本檔內部實作。"""


def handler(event, context):
    symbols = (event or {}).get("symbols") or []
    news = [
        {
            "symbol": s,
            "headline": f"{s} 近期無重大個別消息,市場關注整體產業景氣與資金流向。",
            "sentiment": "neutral",
        }
        for s in symbols
    ]
    return {"is_mock": True, "news": news}
```

`tools/get_chip_data.py`:
```python
"""Gateway tool(mock):固定法人買賣超樣板。真資料(主辦方籌碼資料)到位後只換本檔。"""


def handler(event, context):
    symbols = (event or {}).get("symbols") or []
    chips = [
        {
            "symbol": s,
            "foreign_net_buy_lots": 0,
            "trust_net_buy_lots": 0,
            "note": "示意資料:近五日法人進出接近中性,無明顯方向。",
        }
        for s in symbols
    ]
    return {"is_mock": True, "chips": chips}
```

- [ ] **Step 4: 跑全部工具測試**

```bash
python -m pytest tests/tools -v
```
Expected: 7 PASS。

- [ ] **Step 5: Commit**

```bash
git add tools/get_latest_news.py tools/get_chip_data.py tests/tools/test_mock_tools.py
git commit -m "feat: mock gateway tools (news, chip data) with locked contracts"
```

---

### Task 4: CDK Gateway Stack(Gateway + 4 Lambda + IAM + SSM)

**Files:**
- Create: `infra/app.py`
- Create: `infra/cdk.json`
- Create: `infra/requirements.txt`
- Create: `infra/stacks/__init__.py`
- Create: `infra/stacks/gateway_stack.py`
- Test: `infra/tests/__init__.py`, `infra/tests/test_gateway_stack.py`

**Interfaces:**
- Consumes: `tools/` 目錄(Lambda asset)。
- Produces: CloudFormation stack `StockMood-AgentCoreGateway`,輸出 `GatewayUrl`;SSM 參數 `/stockmood/agentcore/gateway-url`。CDK context `backend_base_url` 必填。
- Gateway:MCP protocol、`AWS_IAM` authorizer。4 個 target 各掛一個 Lambda,工具名:`get_portfolio_holdings` / `get_market_compare` / `get_latest_news` / `get_chip_data`(Gateway 端呈現為 `<target-name>___<tool-name>`)。

- [ ] **Step 1: 寫失敗測試**

`infra/tests/test_gateway_stack.py`:
```python
import aws_cdk as cdk
import pytest
from aws_cdk.assertions import Match, Template

from stacks.gateway_stack import GatewayStack

TAGS = {"Project": "StockMood-Hackathon", "Environment": "hackathon", "ManagedBy": "CDK"}


@pytest.fixture(scope="module")
def template():
    app = cdk.App(context={"backend_base_url": "https://backend.example"})
    stack = GatewayStack(app, "TestGw", env=cdk.Environment(region="us-east-1"))
    for k, v in TAGS.items():
        cdk.Tags.of(app).add(k, v)
    return Template.from_stack(stack)


def test_gateway_uses_iam_auth(template):
    template.has_resource_properties(
        "AWS::BedrockAgentCore::Gateway",
        {"AuthorizerType": "AWS_IAM", "ProtocolType": "MCP"},
    )


def test_four_lambda_targets(template):
    template.resource_count_is("AWS::BedrockAgentCore::GatewayTarget", 4)
    template.resource_count_is("AWS::Lambda::Function", 4)


def test_backend_lambdas_get_base_url_env(template):
    template.has_resource_properties(
        "AWS::Lambda::Function",
        {
            "Handler": "get_portfolio_holdings.handler",
            "Environment": {"Variables": {"BACKEND_BASE_URL": "https://backend.example"}},
        },
    )


def test_gateway_url_in_ssm(template):
    template.has_resource_properties(
        "AWS::SSM::Parameter",
        {"Name": "/stockmood/agentcore/gateway-url"},
    )


def test_lambda_has_project_tag(template):
    template.has_resource_properties(
        "AWS::Lambda::Function",
        Match.object_like(
            {"Tags": Match.array_with([{"Key": "Project", "Value": "StockMood-Hackathon"}])}
        ),
    )
```

- [ ] **Step 2: 跑測試,確認失敗**

```bash
cd infra && python -m pytest tests -v; cd ..
```
Expected: FAIL(`ModuleNotFoundError: stacks`)。(infra 測試在 `infra/` 目錄下跑,獨立於 root pytest.ini——把 root `pytest.ini` 的 `testpaths` 改回只有 `tests`,infra 測試由 `cd infra && python -m pytest tests` 跑,比照 AwsStockApp 慣例。)

- [ ] **Step 3: 實作 stack**

`infra/requirements.txt`:
```
aws-cdk-lib>=2.220.0,<3.0.0
constructs>=10.0.0,<11.0.0
pytest>=7.3.0
```

`infra/cdk.json`:
```json
{
  "app": "python app.py"
}
```

`infra/app.py`:
```python
#!/usr/bin/env python3
import aws_cdk as cdk

from stacks.gateway_stack import GatewayStack

TAGS = {
    "Project": "StockMood-Hackathon",
    "Environment": "hackathon",
    "ManagedBy": "CDK",
}

app = cdk.App()
GatewayStack(app, "StockMood-AgentCoreGateway", env=cdk.Environment(region="us-east-1"))

for k, v in TAGS.items():
    cdk.Tags.of(app).add(k, v)

app.synth()
```

`infra/stacks/gateway_stack.py`:
```python
"""AgentCore Gateway + 4 個 Lambda tool。

Gateway 用 AWS_IAM(SigV4)inbound auth,免 Cognito;
Gateway URL 寫入 SSM 供 agent 冷啟動讀取。
"""
from aws_cdk import (
    CfnOutput,
    Duration,
    Stack,
    aws_bedrockagentcore as agentcore,
    aws_iam as iam,
    aws_lambda as _lambda,
    aws_ssm as ssm,
)
from constructs import Construct

GATEWAY_URL_PARAM = "/stockmood/agentcore/gateway-url"

# (工具名, 說明, 輸入 schema)
TOOLS = [
    (
        "get_portfolio_holdings",
        "取得使用者的庫存分析:總市值、未實現損益、風險分數、產業曝險、持股明細與風險提醒。",
        {
            "type": "object",
            "properties": {"user_id": {"type": "string", "description": "使用者 ID"}},
            "required": ["user_id"],
        },
    ),
    (
        "get_market_compare",
        "取得使用者投組與大盤(加權指數)的今日表現比較。",
        {
            "type": "object",
            "properties": {"user_id": {"type": "string", "description": "使用者 ID"}},
            "required": ["user_id"],
        },
    ),
    (
        "get_latest_news",
        "取得指定股票代號的最新市場資訊摘要(目前為示意資料)。",
        {
            "type": "object",
            "properties": {
                "symbols": {"type": "array", "items": {"type": "string"}, "description": "股票代號清單"}
            },
            "required": ["symbols"],
        },
    ),
    (
        "get_chip_data",
        "取得指定股票代號的法人籌碼進出概況(目前為示意資料)。",
        {
            "type": "object",
            "properties": {
                "symbols": {"type": "array", "items": {"type": "string"}, "description": "股票代號清單"}
            },
            "required": ["symbols"],
        },
    ),
]

BACKEND_TOOLS = {"get_portfolio_holdings", "get_market_compare"}


class GatewayStack(Stack):
    def __init__(self, scope: Construct, cid: str, **kwargs) -> None:
        super().__init__(scope, cid, **kwargs)

        backend_base_url = self.node.try_get_context("backend_base_url")
        if not backend_base_url:
            raise ValueError("缺 CDK context backend_base_url(-c backend_base_url=https://...)")

        code = _lambda.Code.from_asset("../tools")
        functions: dict[str, _lambda.Function] = {}
        for name, _desc, _schema in TOOLS:
            env = {"BACKEND_BASE_URL": backend_base_url} if name in BACKEND_TOOLS else {}
            functions[name] = _lambda.Function(
                self,
                f"Fn-{name}",
                function_name=f"stockmood-agentcore-{name.replace('_', '-')}",
                runtime=_lambda.Runtime.PYTHON_3_13,
                handler=f"{name}.handler",
                code=code,
                timeout=Duration.seconds(10),
                environment=env,
            )

        gateway_role = iam.Role(
            self,
            "GatewayRole",
            assumed_by=iam.ServicePrincipal("bedrock-agentcore.amazonaws.com"),
        )
        for fn in functions.values():
            fn.grant_invoke(gateway_role)

        gateway = agentcore.CfnGateway(
            self,
            "Gateway",
            name="stockmood-portfolio-insight",
            protocol_type="MCP",
            authorizer_type="AWS_IAM",
            role_arn=gateway_role.role_arn,
            description="StockMood portfolio insight tools",
        )

        for name, desc, schema in TOOLS:
            agentcore.CfnGatewayTarget(
                self,
                f"Target-{name}",
                gateway_identifier=gateway.attr_gateway_identifier,
                name=name.replace("_", "-"),
                credential_provider_configurations=[
                    agentcore.CfnGatewayTarget.CredentialProviderConfigurationProperty(
                        credential_provider_type="GATEWAY_IAM_ROLE"
                    )
                ],
                target_configuration=agentcore.CfnGatewayTarget.TargetConfigurationProperty(
                    mcp=agentcore.CfnGatewayTarget.McpTargetConfigurationProperty(
                        lambda_=agentcore.CfnGatewayTarget.McpLambdaTargetConfigurationProperty(
                            lambda_arn=functions[name].function_arn,
                            tool_schema=agentcore.CfnGatewayTarget.ToolSchemaProperty(
                                inline_payload=[
                                    agentcore.CfnGatewayTarget.ToolDefinitionProperty(
                                        name=name,
                                        description=desc,
                                        input_schema=schema,
                                    )
                                ]
                            ),
                        )
                    )
                ),
            )

        ssm.StringParameter(
            self,
            "GatewayUrlParam",
            parameter_name=GATEWAY_URL_PARAM,
            string_value=gateway.attr_gateway_url,
        )
        CfnOutput(self, "GatewayUrl", value=gateway.attr_gateway_url)
        CfnOutput(self, "GatewayArn", value=gateway.attr_gateway_arn)
```

**若 synth 對 `CfnGatewayTarget` 巢狀 property 名稱報錯**(此 L1 介面較新,欄位名以安裝版 CDK 為準):以 `python -c "from aws_cdk import aws_bedrockagentcore as a; help(a.CfnGatewayTarget)"` 或 CDK Python 文件確認實際 property 類名後修正;schema 若不接受 dict,改傳對應的 property 物件。不可為省事改走 boto3 腳本建 Gateway。

- [ ] **Step 4: 跑測試,確認通過**

```bash
cd infra && pip install -r requirements.txt && python -m pytest tests -v; cd ..
```
Expected: 5 PASS。

- [ ] **Step 5: Commit**

```bash
git add infra/ pytest.ini
git commit -m "feat: CDK stack for AgentCore gateway with 4 lambda tool targets"
```

---

### Task 5: 部署 Gateway 並煙霧測試(真 AWS)

**Files:**
- Create: `scripts/deploy_gateway.sh`
- Create: `scripts/gateway_smoke.py`

**Interfaces:**
- Consumes: Task 4 的 stack;環境變數 `BACKEND_BASE_URL`。
- Produces: 已部署的 Gateway(URL 在 SSM `/stockmood/agentcore/gateway-url`);`gateway_smoke.py` 驗證 4 工具可列出、`get_portfolio_holdings` 可呼叫且回真實資料。

- [ ] **Step 1: 寫 `scripts/deploy_gateway.sh`**

```bash
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
[[ -d .venv ]] || python -m venv .venv
source .venv/Scripts/activate 2>/dev/null || source .venv/bin/activate
pip install -q -r requirements.txt

npx cdk deploy StockMood-AgentCoreGateway \
  --profile "$PROFILE" --region "$REGION" \
  -c backend_base_url="$BACKEND_BASE_URL" \
  --require-approval never

echo "Gateway URL:"
aws ssm get-parameter --name /stockmood/agentcore/gateway-url \
  --profile "$PROFILE" --region "$REGION" --query Parameter.Value --output text
```

- [ ] **Step 2: 寫 `scripts/gateway_smoke.py`**

```python
"""Gateway 煙霧測試:SigV4 連 MCP endpoint,列工具、實呼叫 get_portfolio_holdings。

用法: AWS_PROFILE=dev python scripts/gateway_smoke.py [--user-id demo-user]
需要: pip install mcp-proxy-for-aws (含 mcp 依賴)
"""
import argparse
import asyncio
import json

import boto3
from mcp import ClientSession
from mcp_proxy_for_aws.client import aws_iam_streamablehttp_client

REGION = "us-east-1"
PARAM = "/stockmood/agentcore/gateway-url"


async def main(user_id: str) -> None:
    gateway_url = boto3.client("ssm", region_name=REGION).get_parameter(Name=PARAM)[
        "Parameter"
    ]["Value"]
    print(f"Gateway: {gateway_url}")

    async with aws_iam_streamablehttp_client(
        endpoint=gateway_url, aws_region=REGION, aws_service="bedrock-agentcore"
    ) as (read, write, _):
        async with ClientSession(read, write) as session:
            await session.initialize()
            tools = await session.list_tools()
            names = [t.name for t in tools.tools]
            print(f"tools ({len(names)}): {names}")
            assert len(names) == 4, "應有 4 個工具"

            holdings_tool = next(n for n in names if "get_portfolio_holdings" in n)
            result = await session.call_tool(holdings_tool, {"user_id": user_id})
            payload = json.loads(result.content[0].text)
            print(json.dumps(payload, ensure_ascii=False, indent=2)[:800])
            assert "error" not in payload, f"工具回錯誤: {payload}"
            assert "risk_score" in payload, "應含規則式風險分數"
    print("SMOKE OK")


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("--user-id", default="demo-user")
    asyncio.run(main(p.parse_args().user_id))
```

(若 `aws_iam_streamablehttp_client` 的參數簽名與此不符——該套件較新——以 `pip show mcp-proxy-for-aws` 裝到的版本原始碼為準修正呼叫方式,語意不變:endpoint + region + service=bedrock-agentcore 的 SigV4 streamable HTTP client。)

- [ ] **Step 3: 跟使用者確認後端 URL 仍有效,然後部署**

先打一發確認:
```bash
curl -s -o /dev/null -w "%{http_code}" https://st-2f8caae5711f455a9318dbe4a15ec9a2.ecs.us-east-1.on.aws/health
```
Expected: `200`(若非 200,停下向使用者要新 URL)。

```bash
pip install mcp-proxy-for-aws
BACKEND_BASE_URL=https://st-2f8caae5711f455a9318dbe4a15ec9a2.ecs.us-east-1.on.aws \
  AWS_PROFILE=dev ./scripts/deploy_gateway.sh
```
Expected: CloudFormation CREATE_COMPLETE,印出 Gateway URL。

- [ ] **Step 4: 跑煙霧測試**

```bash
AWS_PROFILE=dev python scripts/gateway_smoke.py --user-id demo-user
```
Expected: 列出 4 工具、印出含 `risk_score` 的真實庫存分析 JSON、`SMOKE OK`。

- [ ] **Step 5: Commit**

```bash
git add scripts/deploy_gateway.sh scripts/gateway_smoke.py
git commit -m "feat: gateway deploy script + SigV4 MCP smoke test"
```

---

### Task 6: Agent 專案 scaffold(AgentCore CLI)與本機跑通

**Files:**
- Create: `PortfolioInsight/`(由 `agentcore create` 產生:`agentcore/agentcore.json`、`aws-targets.json`、`app/PortfolioInsight/main.py`、`pyproject.toml`)

**Interfaces:**
- Produces: 可 `agentcore dev` 本機執行的 Strands agent 專案;region 已鎖 us-east-1。此時 agent 還是 scaffold 內容,尚未接 Gateway(Task 7)。

- [ ] **Step 1: scaffold**

```bash
cd "D:/國泰/01_2026黑客松_AWSxCmoney/AgentCore"
agentcore create --name PortfolioInsight --framework Strands --protocol HTTP \
  --model-provider Bedrock --memory none --build CodeZip
```
Expected: 產生 `PortfolioInsight/` 目錄(agentcore/ 設定 + app/ 程式碼)。

- [ ] **Step 2: 鎖 region/帳號**

編輯 `PortfolioInsight/agentcore/aws-targets.json`,把 region 設為 `us-east-1`(預設是 us-west-2)、帳號對應 dev profile(475794918554)。確切欄位名以產生的檔案為準。

- [ ] **Step 3: 模型改 sonnet-4-5**

在 `PortfolioInsight/app/PortfolioInsight/main.py`(scaffold 的 Strands agent),把模型設為:
```python
model = "us.anthropic.claude-sonnet-4-5-20250929-v1:0"
```
(scaffold 若用 `BedrockModel(model_id=...)` 就改 model_id;確切寫法以 scaffold 為準,只動模型字串。)

- [ ] **Step 4: 本機驗證 scaffold 可跑**

```bash
cd PortfolioInsight
AWS_PROFILE=dev agentcore dev --logs &   # 或另開終端跑前景
sleep 20
AWS_PROFILE=dev agentcore dev "你好,請自我介紹"
```
Expected: 回覆一段文字(模型經 Bedrock 正常回應)。若 AccessDenied → 按 Global Constraints 的 Bedrock 檢查程序。驗完停掉 dev server。

- [ ] **Step 5: Commit**

```bash
cd ..
git add PortfolioInsight/
git commit -m "feat: scaffold PortfolioInsight agent project (Strands, us-east-1, sonnet-4-5)"
```

---

### Task 7: Agent 接 Gateway + 洞察生成邏輯

**Files:**
- Modify: `PortfolioInsight/app/PortfolioInsight/main.py`(全部重寫 entrypoint 邏輯,保留 scaffold 的 app 框架結構)
- Modify: `PortfolioInsight/app/PortfolioInsight/pyproject.toml`(加依賴)

**Interfaces:**
- Consumes: SSM `/stockmood/agentcore/gateway-url`(Task 5 已部署)。
- Produces: entrypoint 輸入 `{"user_id": "<id>"}`,輸出:
  ```json
  {"insight_summary": "…", "holding_notes": [{"symbol": "2330", "note": "…"}]}
  ```
  全工具失敗時輸出 fallback(`insight_summary` 為安全安撫文字、`holding_notes` 空陣列),絕不 raise。

- [ ] **Step 1: 加依賴**

`pyproject.toml` dependencies 加入(scaffold 已含 strands/bedrock-agentcore 相關,補缺的):
```toml
"mcp-proxy-for-aws",
"boto3",
```

- [ ] **Step 2: 實作 main.py**

保留 scaffold 的 `BedrockAgentCoreApp`/entrypoint 結構(以 scaffold 實際樣板為準),核心邏輯替換為:

```python
"""portfolio_insight_agent:疊加在規則式庫存分析上的洞察生成。"""
import json
import os

import boto3
from strands import Agent
from strands.tools.mcp import MCPClient
from mcp_proxy_for_aws.client import aws_iam_streamablehttp_client

REGION = os.environ.get("AWS_REGION", "us-east-1")
MODEL_ID = os.environ.get("MODEL_ID", "us.anthropic.claude-sonnet-4-5-20250929-v1:0")
GATEWAY_URL_PARAM = "/stockmood/agentcore/gateway-url"

SYSTEM_PROMPT = """你是 StockMood 的投資陪伴分析師,服務投資新手。

規則(不可違反):
1. 一律使用繁體中文,語氣溫和安撫,像朋友聊天,不用術語轟炸。
2. 絕對不可以出現任何買進、賣出、加碼、減碼、停損等具體操作建議字眼。
3. 只能使用工具回傳的實際數字,不得捏造或推算工具沒提供的數值。
4. 工具回傳 is_mock=true 的資料,只能當背景氛圍參考,不可引用其中數字。
5. 工具回傳 error 時,坦白說「這部分資料暫時取不到」,不要編內容。

任務:先呼叫 get_portfolio_holdings 取得使用者的庫存分析(規則式數字已算好),
視需要再呼叫 get_market_compare / get_latest_news / get_chip_data 補脈絡。
然後輸出 JSON(只輸出 JSON,不要其他文字):
{"insight_summary": "整體洞察,150 字內,基於風險分數、產業曝險與風險提醒,\
   給使用者「知道自己投組長什麼樣子」的安心感",
 "holding_notes": [{"symbol": "代號", "note": "一句話短評,30 字內"}]}
holding_notes 依權重排序,最多 5 檔。"""

FALLBACK = {
    "insight_summary": "目前分析資料暫時取不到,你的持股數字本身沒有變化,"
    "不用因為看不到分析而緊張;稍後再回來看看就好。",
    "holding_notes": [],
}

_gateway_url = None


def _get_gateway_url() -> str:
    global _gateway_url
    if _gateway_url is None:
        _gateway_url = os.environ.get("GATEWAY_URL") or boto3.client(
            "ssm", region_name=REGION
        ).get_parameter(Name=GATEWAY_URL_PARAM)["Parameter"]["Value"]
    return _gateway_url


def _parse_agent_json(text: str) -> dict:
    """模型輸出→dict;容忍 ```json 圍欄與前後雜訊。"""
    cleaned = text.strip()
    if "```" in cleaned:
        cleaned = cleaned.split("```")[1].removeprefix("json").strip()
    start, end = cleaned.find("{"), cleaned.rfind("}")
    if start == -1 or end == -1:
        raise ValueError("no JSON object in model output")
    data = json.loads(cleaned[start : end + 1])
    if "insight_summary" not in data:
        raise ValueError("missing insight_summary")
    data.setdefault("holding_notes", [])
    return data


def generate_insight(user_id: str) -> dict:
    try:
        mcp_client = MCPClient(
            lambda: aws_iam_streamablehttp_client(
                endpoint=_get_gateway_url(),
                aws_region=REGION,
                aws_service="bedrock-agentcore",
            )
        )
        with mcp_client:
            tools = mcp_client.list_tools_sync()
            agent = Agent(model=MODEL_ID, tools=tools, system_prompt=SYSTEM_PROMPT)
            result = agent(f"請為 user_id={user_id} 的使用者產生庫存分析洞察。")
        return _parse_agent_json(str(result))
    except Exception:  # noqa: BLE001 — 對呼叫端絕不 raise
        return FALLBACK
```

entrypoint(接 scaffold 的 `@app.entrypoint`):
```python
@app.entrypoint
def invoke(payload, context=None):
    user_id = (payload or {}).get("user_id") or (payload or {}).get("prompt", "demo-user")
    return generate_insight(str(user_id).strip() or "demo-user")
```

(`prompt` fallback 是為了 `agentcore dev "..."` / `agentcore invoke "..."` 這種純文字測試路徑也能動。)

- [ ] **Step 3: 本機端到端驗證(打真 Gateway + 真後端)**

```bash
cd PortfolioInsight
AWS_PROFILE=dev agentcore dev --logs &
sleep 20
AWS_PROFILE=dev agentcore dev "demo-user"
```
Expected: 回傳 JSON,`insight_summary` 為繁中安撫語氣、引用真實風險分數/產業曝險;`holding_notes` 有內容。人工檢查:(1) 無買賣建議字眼 (2) 數字與 `gateway_smoke.py` 看到的一致、無捏造 (3) mock 工具數字未被引用。

- [ ] **Step 4: 驗證 fallback 路徑**

暫時把 `GATEWAY_URL` 設成壞網址跑一次:
```bash
GATEWAY_URL=https://invalid.example AWS_PROFILE=dev agentcore dev "demo-user"
```
Expected: 回 FALLBACK JSON,不噴 exception。(注意 `_gateway_url` 有 cache,dev server 要重啟後測。)

- [ ] **Step 5: Commit**

```bash
cd ..
git add PortfolioInsight/
git commit -m "feat: wire agent to gateway via SigV4 MCP with insight generation + fallback"
```

---

### Task 8: 部署 Runtime 並雲端煙霧測試

**Files:**
- Create: `scripts/deploy_runtime.sh`
- Create: `scripts/invoke_test.py`

**Interfaces:**
- Consumes: Task 5 的 Gateway、Task 7 的 agent。
- Produces: 已部署的 AgentCore Runtime;runtime 執行角色補上 SSM 讀取與 Gateway invoke 權限;`invoke_test.py` 可從本機 invoke 雲端 agent。

- [ ] **Step 1: 寫 `scripts/deploy_runtime.sh`**

```bash
#!/usr/bin/env bash
#
# 部署 PortfolioInsight agent 到 AgentCore Runtime,並補 runtime 角色權限。
# 用法: AWS_PROFILE=dev ./scripts/deploy_runtime.sh
set -euo pipefail

PROFILE="${AWS_PROFILE:-dev}"
REGION="us-east-1"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

cd "$ROOT/PortfolioInsight"
AWS_PROFILE="$PROFILE" agentcore deploy -y

# ── 補 runtime 執行角色權限:讀 SSM gateway-url + invoke gateway(SigV4) ──
ACCOUNT=$(aws sts get-caller-identity --profile "$PROFILE" --query Account --output text)
GATEWAY_ARN=$(aws cloudformation describe-stacks --stack-name StockMood-AgentCoreGateway \
  --profile "$PROFILE" --region "$REGION" \
  --query "Stacks[0].Outputs[?OutputKey=='GatewayArn'].OutputValue" --output text)

# CLI 建的執行角色:從其 CloudFormation stack 找 IAM Role(名稱含 BedrockAgentCore)
ROLE_NAME=$(aws iam list-roles --profile "$PROFILE" \
  --query "Roles[?contains(RoleName, 'PortfolioInsight')].RoleName | [0]" --output text)
if [[ "$ROLE_NAME" == "None" || -z "$ROLE_NAME" ]]; then
  echo "ERROR: 找不到 runtime 執行角色;用 'agentcore status' 確認角色名後設 RUNTIME_ROLE_NAME 重跑" >&2
  exit 1
fi
ROLE_NAME="${RUNTIME_ROLE_NAME:-$ROLE_NAME}"
echo "Runtime role: $ROLE_NAME"

aws iam put-role-policy --profile "$PROFILE" --role-name "$ROLE_NAME" \
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
```
(角色查找依 CLI 實際命名而定;若 `PortfolioInsight` 關鍵字撈不到,跑 `agentcore status` 看 stack 名,再 `aws cloudformation describe-stack-resources` 找 `AWS::IAM::Role`,把正確名稱經 `RUNTIME_ROLE_NAME` 傳入。)

- [ ] **Step 2: 寫 `scripts/invoke_test.py`**

```python
"""從本機 invoke 已部署的 AgentCore Runtime,人工檢查洞察品質。

用法: AWS_PROFILE=dev python scripts/invoke_test.py --user-id demo-user
"""
import argparse
import json
import uuid

import boto3

REGION = "us-east-1"


def find_runtime_arn(client) -> str:
    runtimes = client.list_agent_runtimes()["agentRuntimes"]
    matches = [r for r in runtimes if "portfolioinsight" in r["agentRuntimeName"].lower()]
    assert matches, f"找不到 PortfolioInsight runtime,現有: {[r['agentRuntimeName'] for r in runtimes]}"
    return matches[0]["agentRuntimeArn"]


def main(user_id: str) -> None:
    control = boto3.client("bedrock-agentcore-control", region_name=REGION)
    arn = find_runtime_arn(control)
    print(f"Runtime: {arn}")

    client = boto3.client("bedrock-agentcore", region_name=REGION)
    resp = client.invoke_agent_runtime(
        agentRuntimeArn=arn,
        runtimeSessionId=str(uuid.uuid4()),
        payload=json.dumps({"user_id": user_id}).encode(),
        qualifier="DEFAULT",
    )
    body = "".join(chunk.decode() for chunk in resp.get("response", []))
    data = json.loads(body)
    print(json.dumps(data, ensure_ascii=False, indent=2))

    assert "insight_summary" in data, "缺 insight_summary"
    banned = ["買進", "賣出", "加碼", "減碼", "停損"]
    text = json.dumps(data, ensure_ascii=False)
    hits = [w for w in banned if w in text]
    assert not hits, f"出現禁用字眼: {hits}"
    print("INVOKE OK")


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("--user-id", default="demo-user")
    main(p.parse_args().user_id)
```

- [ ] **Step 3: 部署**

```bash
AWS_PROFILE=dev ./scripts/deploy_runtime.sh
```
Expected: CloudFormation 部署成功、印出 runtime role 名稱與 put-role-policy 成功。

- [ ] **Step 4: 雲端煙霧測試**

```bash
AWS_PROFILE=dev python scripts/invoke_test.py --user-id demo-user
```
Expected: 印出洞察 JSON、`INVOKE OK`。同時人工檢查語氣與數字真實性。若失敗,`cd PortfolioInsight && agentcore logs` 看 runtime log 排錯(常見:角色權限沒生效——等 30 秒重試;SSM 參數讀不到——確認 policy resource 拼寫)。

- [ ] **Step 5: Commit**

```bash
git add scripts/deploy_runtime.sh scripts/invoke_test.py
git commit -m "feat: runtime deploy script with role grants + cloud invoke smoke test"
```

---

### Task 9: destroy 腳本、README(最終部署順序)、收尾

**Files:**
- Create: `scripts/destroy.sh`
- Modify: `README.md`

**Interfaces:**
- Produces: 一鍵清除;README 記載**經驗證的最終部署順序**(使用者明確要求)。

- [ ] **Step 1: 寫 `scripts/destroy.sh`**

```bash
#!/usr/bin/env bash
#
# 清除 AgentCore 全部資源:Runtime(CLI 管的 stack)→ Gateway(CDK stack)。
# 用法: AWS_PROFILE=dev ./scripts/destroy.sh
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
source .venv/Scripts/activate 2>/dev/null || source .venv/bin/activate
npx cdk destroy StockMood-AgentCoreGateway --profile "$PROFILE" --region "$REGION" --force \
  -c backend_base_url=placeholder

echo "清除完成。用 Tag Editor 檢查 Project=StockMood-Hackathon 是否還有 AgentCore 相關殘留。"
```
(注意:`agentcore remove all` 會改寫本地 `agentcore.json`——destroy 驗證後記得 `git checkout -- PortfolioInsight/agentcore/` 還原設定檔。)

- [ ] **Step 2: 更新 README——最終可成功部署的腳本順序**

在 `README.md` 加上(以實測成功的實際順序為準,若執行中有調整,寫「真的成功的那套」):

```markdown
## 部署順序(從零到可 invoke,實測通過)

前置:Node 20+、`npm install -g @aws/agentcore`、Python 3.11+、AWS profile `dev`(us-east-1)、
帳號已 `cdk bootstrap`(AwsStockApp Phase 1 已做過)、Bedrock 已可用 claude-sonnet-4-5。

​```bash
# 0. 確認後端現行 URL(ECS Express 每次重部署會換網域!)
curl -s -o /dev/null -w "%{http_code}" $BACKEND_BASE_URL/health   # 要 200

# 1. Gateway + Lambda tools(CDK)
BACKEND_BASE_URL=https://<現行後端網域> AWS_PROFILE=dev ./scripts/deploy_gateway.sh

# 2. Gateway 煙霧測試(SigV4 MCP:列工具 + 實呼叫)
AWS_PROFILE=dev python scripts/gateway_smoke.py --user-id demo-user

# 3. Agent Runtime(AgentCore CLI + 角色權限)
AWS_PROFILE=dev ./scripts/deploy_runtime.sh

# 4. 雲端 invoke 驗證
AWS_PROFILE=dev python scripts/invoke_test.py --user-id demo-user
​```

清除:`AWS_PROFILE=dev ./scripts/destroy.sh`
後端換網域後:只需重跑步驟 1(帶新 URL)——Lambda env 更新,Gateway/Runtime 不用動。
```

- [ ] **Step 3: 全套測試最後跑一次**

```bash
python -m pytest tests -v
cd infra && python -m pytest tests -v; cd ..
AWS_PROFILE=dev python scripts/gateway_smoke.py
AWS_PROFILE=dev python scripts/invoke_test.py
```
Expected: 全綠 + 兩個煙霧測試 OK。

- [ ] **Step 4: Commit**

```bash
git add scripts/destroy.sh README.md
git commit -m "docs: verified end-to-end deploy order + destroy script"
```

- [ ] **Step 5: 回報**

向使用者總結:部署了哪些資源、invoke 範例輸出、README 部署順序位置;詢問是否 merge 回 `main`(用 superpowers:finishing-a-development-branch)。
