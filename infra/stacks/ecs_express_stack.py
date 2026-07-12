from aws_cdk import Stack, CfnOutput
from aws_cdk import aws_ec2 as ec2
from aws_cdk import aws_iam as iam
from aws_cdk import aws_ecr as ecr
from aws_cdk import aws_rds as rds
from aws_cdk import aws_secretsmanager as secretsmanager
from aws_cdk import aws_ecs as ecs
from constructs import Construct


class EcsExpressStack(Stack):
    """核心 API 以 Amazon ECS Express Mode 部署(App Runner 已於 2026 進維護模式)。

    Express Mode 自動建 ALB / SSL / autoscaling / 網路;我們指定既有 VPC 的
    app 私網 + service SG,讓容器連得到私有子網的 RDS。
    """

    def __init__(self, scope: Construct, cid: str, *, vpc: ec2.Vpc,
                 service_sg: ec2.SecurityGroup, ecr_repo: ecr.Repository,
                 db: rds.DatabaseInstance, db_secret_arn: str,
                 app_secret: secretsmanager.Secret, **kwargs) -> None:
        super().__init__(scope, cid, **kwargs)

        # Infrastructure role:讓 ECS Express 代為建 ALB / SG / ACM 憑證 / autoscaling
        infra_role = iam.Role(
            self, "InfraRole",
            assumed_by=iam.ServicePrincipal("ecs.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AmazonECSInfrastructureRoleforExpressGatewayServices"
                )
            ],
        )

        # Execution role:拉 ECR 映像 + 在容器啟動時注入 Secrets Manager 密鑰
        execution_role = iam.Role(
            self, "ExecutionRole",
            assumed_by=iam.ServicePrincipal("ecs-tasks.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AmazonECSTaskExecutionRolePolicy"
                )
            ],
        )
        app_secret.grant_read(execution_role)

        # Task role:執行中容器的身分 → 呼叫 Bedrock + 讀 RDS 密鑰(aws_secrets.py boto3 抓取)
        task_role = iam.Role(
            self, "TaskRole",
            assumed_by=iam.ServicePrincipal("ecs-tasks.amazonaws.com"),
        )
        task_role.add_to_policy(iam.PolicyStatement(
            actions=["bedrock:InvokeModel"],
            resources=["*"],
        ))
        db.secret.grant_read(task_role)

        # service_sg 由 Network stack 建立並已授權連 RDS(避免依賴環)。
        # ECS Express 由子網型別決定 ALB 對外與否:public 子網 → internet-facing ALB
        # (iOS 要能連)。task 落在 public 子網會取得 public IP,但仍受 service_sg 保護
        # (只有 ALB 能打 app port);RDS 仍在 isolated 子網,不對外。
        subnet_ids = [s.subnet_id for s in vpc.select_subnets(
            subnet_type=ec2.SubnetType.PUBLIC).subnets]

        service = ecs.CfnExpressGatewayService(
            self, "ApiService",
            service_name="stockmood-api",
            execution_role_arn=execution_role.role_arn,
            infrastructure_role_arn=infra_role.role_arn,
            task_role_arn=task_role.role_arn,
            cpu="1024",
            memory="2048",
            health_check_path="/health",
            network_configuration=ecs.CfnExpressGatewayService.ExpressGatewayServiceNetworkConfigurationProperty(
                subnets=subnet_ids,
                security_groups=[service_sg.security_group_id],
            ),
            primary_container=ecs.CfnExpressGatewayService.ExpressGatewayContainerProperty(
                image=f"{ecr_repo.repository_uri}:latest",
                container_port=8000,
                environment=[
                    ecs.CfnExpressGatewayService.KeyValuePairProperty(name="AWS_REGION", value="us-east-1"),
                    ecs.CfnExpressGatewayService.KeyValuePairProperty(name="BEDROCK_VISION_MODEL_ID", value="us.anthropic.claude-haiku-4-5-20251001-v1:0"),
                    ecs.CfnExpressGatewayService.KeyValuePairProperty(name="DB_SECRET_ARN", value=db_secret_arn),
                    ecs.CfnExpressGatewayService.KeyValuePairProperty(name="ALLOWED_ORIGINS", value="*"),
                    ecs.CfnExpressGatewayService.KeyValuePairProperty(name="SEED_ON_START", value="true"),
                    ecs.CfnExpressGatewayService.KeyValuePairProperty(name="ALLOW_LEGACY_HEADER_AUTH", value="True"),
                ],
                secrets=[
                    ecs.CfnExpressGatewayService.SecretProperty(
                        name="OPENAI_API_KEY", value_from=f"{app_secret.secret_arn}:OPENAI_API_KEY::"),
                    ecs.CfnExpressGatewayService.SecretProperty(
                        name="JWT_SECRET", value_from=f"{app_secret.secret_arn}:JWT_SECRET::"),
                    ecs.CfnExpressGatewayService.SecretProperty(
                        name="ADMIN_API_KEY", value_from=f"{app_secret.secret_arn}:ADMIN_API_KEY::"),
                ],
            ),
        )
        self.service_ref = service.ref
        CfnOutput(self, "ServiceRef", value=service.ref)
