import aws_cdk as cdk
from aws_cdk.assertions import Template, Match

from stacks.network_stack import NetworkStack
from stacks.data_stack import DataStack
from stacks.ecs_express_stack import EcsExpressStack


def _synth():
    app = cdk.App()
    env = cdk.Environment(region="us-east-1")
    net = NetworkStack(app, "Net", env=env)
    data = DataStack(app, "Data", vpc=net.vpc, db_sg=net.db_sg, env=env)
    ecs_express = EcsExpressStack(
        app, "Ecs", vpc=net.vpc, service_sg=net.service_sg,
        ecr_repo=data.ecr_repo, db=data.db,
        db_secret_arn=data.db_secret_arn, app_secret=data.app_secret, env=env,
    )
    return Template.from_stack(ecs_express)


def test_express_gateway_service_created():
    template = _synth()
    template.resource_count_is("AWS::ECS::ExpressGatewayService", 1)


def test_task_role_can_invoke_bedrock():
    template = _synth()
    # Bedrock InvokeModel 必須出現在某個 IAM policy(task role)
    template.has_resource_properties(
        "AWS::IAM::Policy",
        {
            "PolicyDocument": {
                "Statement": Match.array_with([
                    {"Action": "bedrock:InvokeModel", "Effect": "Allow", "Resource": "*"}
                ])
            }
        },
    )
