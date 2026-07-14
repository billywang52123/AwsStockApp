import aws_cdk as cdk
from aws_cdk.assertions import Template

from stacks.network_stack import NetworkStack
from stacks.data_stack import DataStack


def _synth():
    app = cdk.App()
    env = cdk.Environment(region="us-east-1")
    net = NetworkStack(app, "Net", env=env)
    data = DataStack(app, "Data", vpc=net.vpc, db_sg=net.db_sg, env=env)
    return Template.from_stack(data)


def test_rds_not_publicly_accessible():
    template = _synth()
    template.has_resource_properties("AWS::RDS::DBInstance", {"PubliclyAccessible": False})


def test_ecr_repo_created():
    template = _synth()
    template.resource_count_is("AWS::ECR::Repository", 1)
