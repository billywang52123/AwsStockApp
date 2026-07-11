from aws_cdk import Stack, RemovalPolicy, Duration
from aws_cdk import aws_ec2 as ec2
from aws_cdk import aws_rds as rds
from aws_cdk import aws_ecr as ecr
from aws_cdk import aws_secretsmanager as secretsmanager
from constructs import Construct


class DataStack(Stack):
    def __init__(self, scope: Construct, cid: str, *, vpc: ec2.Vpc,
                 db_sg: ec2.SecurityGroup, **kwargs) -> None:
        super().__init__(scope, cid, **kwargs)

        # RDS PostgreSQL 16,私有隔離子網,憑證自動存 Secrets Manager
        self.db = rds.DatabaseInstance(
            self,
            "StockMoodDb",
            engine=rds.DatabaseInstanceEngine.postgres(
                version=rds.PostgresEngineVersion.VER_16
            ),
            instance_type=ec2.InstanceType.of(
                ec2.InstanceClass.BURSTABLE3, ec2.InstanceSize.MICRO
            ),
            vpc=vpc,
            vpc_subnets=ec2.SubnetSelection(subnet_type=ec2.SubnetType.PRIVATE_ISOLATED),
            security_groups=[db_sg],
            credentials=rds.Credentials.from_generated_secret(
                "stockmood", secret_name="stockmood/db"
            ),
            database_name="stockmood",
            allocated_storage=20,
            publicly_accessible=False,
            removal_policy=RemovalPolicy.DESTROY,   # 黑客松:方便清掉
            delete_automated_backups=True,
            backup_retention=Duration.days(0),
        )
        self.db_secret_arn = self.db.secret.secret_arn

        # 應用層密鑰(手動填值):OPENAI_API_KEY / JWT_SECRET / ADMIN_API_KEY
        self.app_secret = secretsmanager.Secret(
            self,
            "AppSecret",
            secret_name="stockmood/app",
            description="StockMood app-level secrets (OPENAI_API_KEY / JWT_SECRET / ADMIN_API_KEY)",
        )

        # 容器映像倉庫
        self.ecr_repo = ecr.Repository(
            self,
            "ApiRepo",
            repository_name="stockmood-api",
            removal_policy=RemovalPolicy.DESTROY,
            empty_on_delete=True,
        )
