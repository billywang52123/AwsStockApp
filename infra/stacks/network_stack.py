from aws_cdk import Stack
from aws_cdk import aws_ec2 as ec2
from constructs import Construct


class NetworkStack(Stack):
    def __init__(self, scope: Construct, cid: str, **kwargs) -> None:
        super().__init__(scope, cid, **kwargs)

        # nat_gateways=0:ECS Express 的 task 跑在 public 子網(走 IGW 對外),
        # RDS 在 isolated 子網(不對外),app 私有子網目前無人使用 —— NAT 純浪費成本。
        self.vpc = ec2.Vpc(
            self,
            "StockMoodVpc",
            max_azs=2,
            nat_gateways=0,
            subnet_configuration=[
                ec2.SubnetConfiguration(name="public", subnet_type=ec2.SubnetType.PUBLIC, cidr_mask=24),
                ec2.SubnetConfiguration(name="app", subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS, cidr_mask=24),
                ec2.SubnetConfiguration(name="db", subnet_type=ec2.SubnetType.PRIVATE_ISOLATED, cidr_mask=24),
            ],
        )

        # RDS 安全群組:預設不開任何 inbound
        self.db_sg = ec2.SecurityGroup(
            self, "DbSg", vpc=self.vpc, description="StockMood RDS", allow_all_outbound=False
        )

        # ECS Express 服務 SG(掛在 task 上)。在此 stack 建立並授權,避免
        # 跨棧修改 db_sg 造成 Network<->EcsExpress 依賴環。
        self.service_sg = ec2.SecurityGroup(
            self, "ServiceSg", vpc=self.vpc, description="StockMood ECS Express service"
        )
        self.db_sg.add_ingress_rule(self.service_sg, ec2.Port.tcp(5432), "ECS Express to RDS 5432")
