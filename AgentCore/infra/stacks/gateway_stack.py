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

_Schema = agentcore.CfnGatewayTarget.SchemaDefinitionProperty

USER_ID_SCHEMA = _Schema(
    type="object",
    properties={"user_id": _Schema(type="string", description="使用者 ID")},
    required=["user_id"],
)
SYMBOLS_SCHEMA = _Schema(
    type="object",
    properties={
        "symbols": _Schema(
            type="array", items=_Schema(type="string"), description="股票代號清單"
        )
    },
    required=["symbols"],
)

# (工具名, 說明, 輸入 schema)
TOOLS = [
    (
        "get_portfolio_holdings",
        "取得使用者的庫存分析:總市值、未實現損益、風險分數、產業曝險、持股明細與風險提醒。",
        USER_ID_SCHEMA,
    ),
    (
        "get_market_compare",
        "取得使用者投組與大盤(加權指數)的今日表現比較。",
        USER_ID_SCHEMA,
    ),
    (
        "get_latest_news",
        "取得指定股票代號的最新市場資訊摘要(目前為示意資料)。",
        SYMBOLS_SCHEMA,
    ),
    (
        "get_chip_data",
        "取得指定股票代號的法人籌碼進出概況(目前為示意資料)。",
        SYMBOLS_SCHEMA,
    ),
    (
        "get_stock_valuation",
        "取得指定股票的行情估值:收盤價、漲跌幅、本益比、股價淨值比、成交量、總市值。",
        SYMBOLS_SCHEMA,
    ),
    (
        "get_institutional_flow",
        "取得指定股票的法人動向:外資/投信/自營商買賣超張數與持股比率。",
        SYMBOLS_SCHEMA,
    ),
    (
        "get_stock_momentum",
        "取得指定股票的動能指標:創新高、連漲天數、乖離年線、近5/20/60日漲跌幅。",
        SYMBOLS_SCHEMA,
    ),
    (
        "get_forum_sentiment",
        "取得指定股票的社群討論:同學會發文數、看多/看空/中性數量。",
        SYMBOLS_SCHEMA,
    ),
    (
        "get_stock_returns",
        "取得指定股票的報酬率:日/週/月/季/年報酬率與殖利率。",
        SYMBOLS_SCHEMA,
    ),
]

BACKEND_TOOLS = {
    "get_portfolio_holdings",
    "get_market_compare",
    "get_stock_valuation",
    "get_institutional_flow",
    "get_stock_momentum",
    "get_forum_sentiment",
    "get_stock_returns",
}


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
