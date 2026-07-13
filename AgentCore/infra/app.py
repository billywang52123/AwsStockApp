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
