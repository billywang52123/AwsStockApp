import json
from unittest.mock import MagicMock, patch

from app.core import aws_secrets


def test_returns_plain_database_url_when_no_secret_arn():
    with patch.object(aws_secrets.settings, "DB_SECRET_ARN", None), \
         patch.object(aws_secrets.settings, "DATABASE_URL", "sqlite:///./x.db"):
        assert aws_secrets.resolve_database_url() == "sqlite:///./x.db"


def test_builds_postgres_url_from_secret():
    secret = {
        "username": "stockmood",
        "password": "p@ss/w0rd",
        "host": "db.example.rds.amazonaws.com",
        "port": 5432,
        "dbname": "stockmood",
    }
    fake_client = MagicMock()
    fake_client.get_secret_value.return_value = {"SecretString": json.dumps(secret)}
    with patch.object(aws_secrets.settings, "DB_SECRET_ARN", "arn:aws:secretsmanager:...:secret:x"), \
         patch.object(aws_secrets.boto3, "client", return_value=fake_client):
        url = aws_secrets.resolve_database_url()
    # 密碼含特殊字元需 URL-encode
    assert url == (
        "postgresql+psycopg2://stockmood:p%40ss%2Fw0rd@"
        "db.example.rds.amazonaws.com:5432/stockmood"
    )
