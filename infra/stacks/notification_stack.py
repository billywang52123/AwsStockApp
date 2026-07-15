import json
from pathlib import Path

from aws_cdk import Aws, CfnOutput, Duration, RemovalPolicy, Stack
from aws_cdk import aws_cloudwatch as cloudwatch
from aws_cdk import aws_dynamodb as dynamodb
from aws_cdk import aws_ec2 as ec2
from aws_cdk import aws_ecr_assets as ecr_assets
from aws_cdk import aws_iam as iam
from aws_cdk import aws_lambda as lambda_
from aws_cdk import aws_logs as logs
from aws_cdk import aws_scheduler as scheduler
from aws_cdk import aws_secretsmanager as secretsmanager
from constructs import Construct


class NotificationStack(Stack):
    """Personalized holding-signal push Lambda and its private AWS connectivity."""

    def __init__(
        self,
        scope: Construct,
        cid: str,
        *,
        vpc: ec2.Vpc,
        db_sg: ec2.SecurityGroup,
        service_sg: ec2.SecurityGroup,
        db_secret_arn: str,
        **kwargs,
    ) -> None:
        super().__init__(scope, cid, **kwargs)

        app_subnets = vpc.select_subnets(subnet_group_name="app").subnets
        if not app_subnets:
            raise ValueError("Notification Lambda requires the VPC app subnet group")

        lambda_sg = ec2.SecurityGroup(
            self,
            "NotificationLambdaSg",
            vpc=vpc,
            description="StockMood personalized push Lambda",
            allow_all_outbound=True,
        )

        # Keep the ingress resource in this stack. Calling db_sg.add_ingress_rule
        # would mutate the Network stack and create a Network <-> Notifications
        # cross-stack dependency cycle.
        ec2.CfnSecurityGroupIngress(
            self,
            "NotificationLambdaToDb",
            group_id=db_sg.security_group_id,
            ip_protocol="tcp",
            from_port=5432,
            to_port=5432,
            source_security_group_id=lambda_sg.security_group_id,
            description="Notification Lambda to RDS 5432",
        )

        endpoint_sg = ec2.SecurityGroup(
            self,
            "NotificationEndpointSg",
            vpc=vpc,
            description="HTTPS endpoints used by the notification Lambda",
            allow_all_outbound=True,
        )
        endpoint_sg.add_ingress_rule(
            lambda_sg,
            ec2.Port.tcp(443),
            "Notification Lambda to AWS PrivateLink endpoints",
        )
        endpoint_sg.add_ingress_rule(
            service_sg,
            ec2.Port.tcp(443),
            "ECS Express to AWS PrivateLink endpoints",
        )

        # There is intentionally no NAT Gateway in this VPC. A single endpoint
        # ENI per service is sufficient for the demo and avoids a per-AZ fixed
        # cost; Private DNS makes it reachable from either app subnet.
        endpoint_subnets = ec2.SubnetSelection(subnets=[app_subnets[0]])
        ec2.InterfaceVpcEndpoint(
            self,
            "SecretsManagerEndpoint",
            vpc=vpc,
            service=ec2.InterfaceVpcEndpointAwsService.SECRETS_MANAGER,
            subnets=endpoint_subnets,
            security_groups=[endpoint_sg],
            private_dns_enabled=True,
            open=False,
        )
        ec2.InterfaceVpcEndpoint(
            self,
            "SnsEndpoint",
            vpc=vpc,
            service=ec2.InterfaceVpcEndpointAwsService.SNS,
            subnets=endpoint_subnets,
            security_groups=[endpoint_sg],
            private_dns_enabled=True,
            open=False,
        )
        ec2.InterfaceVpcEndpoint(
            self,
            "BedrockRuntimeEndpoint",
            vpc=vpc,
            service=ec2.InterfaceVpcEndpointService(
                name=f"com.amazonaws.{Aws.REGION}.bedrock-runtime",
                port=443,
            ),
            subnets=endpoint_subnets,
            security_groups=[endpoint_sg],
            private_dns_enabled=True,
            open=False,
        )
        ec2.GatewayVpcEndpoint(
            self,
            "DynamoDbEndpoint",
            vpc=vpc,
            service=ec2.GatewayVpcEndpointAwsService.DYNAMODB,
            subnets=[ec2.SubnetSelection(subnet_group_name="app")],
        )

        dedup_table = dynamodb.Table(
            self,
            "NotificationDedupTable",
            table_name="stockmood-notification-dedup",
            partition_key=dynamodb.Attribute(
                name="dedupe_key", type=dynamodb.AttributeType.STRING
            ),
            billing_mode=dynamodb.BillingMode.PAY_PER_REQUEST,
            time_to_live_attribute="expires_at",
            removal_policy=RemovalPolicy.DESTROY,
        )

        function_role = iam.Role(
            self,
            "NotificationLambdaRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaVPCAccessExecutionRole"
                )
            ],
        )
        db_secret = secretsmanager.Secret.from_secret_complete_arn(
            self, "NotificationDbSecret", db_secret_arn
        )
        db_secret.grant_read(function_role)
        dedup_table.grant_read_write_data(function_role)
        function_role.add_to_policy(
            iam.PolicyStatement(actions=["bedrock:InvokeModel"], resources=["*"])
        )
        function_role.add_to_policy(
            iam.PolicyStatement(
                actions=["sns:Publish"],
                resources=[
                    # For mobile push, SNS authorizes Publish against the
                    # platform application ARN even when TargetArn is an
                    # individual endpoint ARN.
                    f"arn:{Aws.PARTITION}:sns:{Aws.REGION}:{Aws.ACCOUNT_ID}:app/APNS/*",
                    f"arn:{Aws.PARTITION}:sns:{Aws.REGION}:{Aws.ACCOUNT_ID}:app/APNS_SANDBOX/*",
                ],
            )
        )

        log_group = logs.LogGroup(
            self,
            "NotificationLambdaLogs",
            log_group_name="/aws/lambda/stockmood-personalized-push",
            retention=logs.RetentionDays.ONE_WEEK,
            removal_policy=RemovalPolicy.DESTROY,
        )

        notifications_dir = Path(__file__).resolve().parents[2] / "notifications"
        push_function = lambda_.DockerImageFunction(
            self,
            "PersonalizedPushFunction",
            function_name="stockmood-personalized-push",
            description="Build one holding-signal candidate per user and publish it through SNS/APNs",
            code=lambda_.DockerImageCode.from_image_asset(
                str(notifications_dir),
                platform=ecr_assets.Platform.LINUX_AMD64,
            ),
            architecture=lambda_.Architecture.X86_64,
            role=function_role,
            memory_size=1024,
            timeout=Duration.minutes(5),
            reserved_concurrent_executions=1,
            vpc=vpc,
            vpc_subnets=ec2.SubnetSelection(subnet_group_name="app"),
            security_groups=[lambda_sg],
            log_group=log_group,
            environment={
                "DB_SECRET_ARN": db_secret_arn,
                "DEDUP_TABLE_NAME": dedup_table.table_name,
                "DEMO_YEAR": "2025",
                "PUSH_DRY_RUN": "true",
                "SIGNAL_THRESHOLD_PERCENT": "2.0",
                "BEDROCK_MODEL_ID": "us.anthropic.claude-sonnet-4-5-20250929-v1:0",
                "LOG_LEVEL": "INFO",
            },
        )

        cloudwatch.Alarm(
            self,
            "NotificationLambdaErrorAlarm",
            alarm_name="stockmood-personalized-push-errors",
            alarm_description="Personalized push Lambda reported an invocation error",
            metric=push_function.metric_errors(period=Duration.minutes(5)),
            threshold=1,
            evaluation_periods=1,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING,
        )

        scheduler_role = iam.Role(
            self,
            "NotificationSchedulerRole",
            assumed_by=iam.ServicePrincipal("scheduler.amazonaws.com"),
        )
        push_function.grant_invoke(scheduler_role)

        schedule_enabled = str(
            self.node.try_get_context("notification_schedule_enabled") or "false"
        ).lower() in {"1", "true", "yes", "on"}
        push_schedule = scheduler.CfnSchedule(
            self,
            "PersonalizedPushSchedule",
            name="stockmood-personalized-push-daily",
            description="Run the 2025 calendar-shift personalized push demo at 14:30 Asia/Taipei",
            state="ENABLED" if schedule_enabled else "DISABLED",
            schedule_expression="cron(30 14 * * ? *)",
            schedule_expression_timezone="Asia/Taipei",
            flexible_time_window=scheduler.CfnSchedule.FlexibleTimeWindowProperty(mode="OFF"),
            target=scheduler.CfnSchedule.TargetProperty(
                arn=push_function.function_arn,
                role_arn=scheduler_role.role_arn,
                input=json.dumps(
                    {
                        "demo_year": 2025,
                        "all_users": True,
                        "dry_run": False,
                        "use_bedrock": True,
                    }
                ),
                retry_policy=scheduler.CfnSchedule.RetryPolicyProperty(
                    maximum_retry_attempts=0,
                ),
            ),
        )

        self.push_function = push_function
        self.push_schedule = push_schedule

        CfnOutput(self, "NotificationFunctionName", value=push_function.function_name)
        CfnOutput(self, "NotificationScheduleName", value=push_schedule.name or "")
        CfnOutput(
            self,
            "NotificationScheduleState",
            value="ENABLED" if schedule_enabled else "DISABLED",
            description="Enable with CDK context notification_schedule_enabled=true after manual testing",
        )
