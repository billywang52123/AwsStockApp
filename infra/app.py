#!/usr/bin/env python3
import aws_cdk as cdk

from stacks.network_stack import NetworkStack
from stacks.data_stack import DataStack
from stacks.ecs_express_stack import EcsExpressStack
from stacks.cognito_stack import CognitoStack

TAGS = {
    "Project": "StockMood-Hackathon",
    "Environment": "hackathon",
    "ManagedBy": "CDK",
}

app = cdk.App()
env = cdk.Environment(region="us-east-1")

network = NetworkStack(app, "StockMood-Network", env=env)
data = DataStack(app, "StockMood-Data", vpc=network.vpc, db_sg=network.db_sg, env=env)
cognito = CognitoStack(app, "StockMood-Cognito", env=env)
ecs_express = EcsExpressStack(
    app, "StockMood-EcsExpress",
    vpc=network.vpc, service_sg=network.service_sg,
    ecr_repo=data.ecr_repo, db=data.db,
    db_secret_arn=data.db_secret_arn, app_secret=data.app_secret,
    cognito_user_pool_id=cognito.user_pool.user_pool_id,
    cognito_app_client_id=cognito.user_pool_client.user_pool_client_id,
    env=env,
)

# 全域 tag:自動蓋到每一個資源
for k, v in TAGS.items():
    cdk.Tags.of(app).add(k, v)

app.synth()
