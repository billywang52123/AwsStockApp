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
