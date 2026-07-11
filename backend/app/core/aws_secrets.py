"""啟動時由 Secrets Manager 抓 RDS 憑證組出 DATABASE_URL。

RDS(CDK `Credentials.fromGeneratedSecret`)產生的密鑰是一段 JSON:
{username, password, host, port, dbname, ...}。App Runner 只注入密鑰 ARN
(非機密),容器用 IAM 權限即時抓取,避免把密碼寫進環境變數或 CFN 模板。
"""

import json
import logging
from urllib.parse import quote_plus

import boto3

from app.core.config import settings

logger = logging.getLogger(__name__)


def resolve_database_url() -> str:
    """有 DB_SECRET_ARN 就從 Secrets Manager 組 Postgres URL,否則回設定值。"""
    if not settings.DB_SECRET_ARN:
        return settings.DATABASE_URL

    client = boto3.client("secretsmanager", region_name=settings.AWS_REGION)
    raw = client.get_secret_value(SecretId=settings.DB_SECRET_ARN)["SecretString"]
    s = json.loads(raw)
    user = quote_plus(str(s["username"]))
    pw = quote_plus(str(s["password"]))
    host = s["host"]
    port = s.get("port", 5432)
    dbname = s.get("dbname", "stockmood")
    logger.info("Resolved DATABASE_URL from secret for host %s", host)
    return f"postgresql+psycopg2://{user}:{pw}@{host}:{port}/{dbname}"
