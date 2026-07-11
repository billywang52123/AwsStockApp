import aws_cdk as cdk
from aws_cdk.assertions import Template, Match

from stacks.network_stack import NetworkStack

TAGS = {"Project": "StockMood-Hackathon", "Environment": "hackathon", "ManagedBy": "CDK"}


def test_vpc_has_project_tag():
    app = cdk.App()
    stack = NetworkStack(app, "TestNet", env=cdk.Environment(region="us-east-1"))
    for k, v in TAGS.items():
        cdk.Tags.of(app).add(k, v)
    template = Template.from_stack(stack)
    template.has_resource_properties(
        "AWS::EC2::VPC",
        {"Tags": Match.array_with([{"Key": "Project", "Value": "StockMood-Hackathon"}])},
    )
