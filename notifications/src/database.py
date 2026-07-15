"""Database access for the personalized push Lambda."""

from __future__ import annotations

import json
import os
from contextlib import contextmanager
from typing import Any, Iterator

import boto3
import psycopg2
from psycopg2.extensions import connection as PgConnection
from psycopg2.extras import RealDictCursor

_secret_cache: dict[str, Any] | None = None
_secrets_client = boto3.client("secretsmanager", region_name=os.getenv("AWS_REGION", "us-east-1"))


def _database_secret() -> dict[str, Any]:
    global _secret_cache
    if _secret_cache is None:
        secret_arn = os.environ["DB_SECRET_ARN"]
        response = _secrets_client.get_secret_value(SecretId=secret_arn)
        _secret_cache = json.loads(response["SecretString"])
    return _secret_cache


@contextmanager
def database_connection() -> Iterator[PgConnection]:
    """Open a short-lived encrypted RDS connection for one Lambda invocation."""
    secret = _database_secret()
    connection = psycopg2.connect(
        host=secret["host"],
        port=int(secret.get("port", 5432)),
        dbname=secret.get("dbname", "stockmood"),
        user=secret["username"],
        password=secret["password"],
        connect_timeout=10,
        sslmode="require",
        application_name="stockmood-personalized-push",
    )
    connection.autocommit = True
    try:
        yield connection
    finally:
        connection.close()


class NotificationRepository:
    def __init__(self, connection: PgConnection):
        self.connection = connection

    def list_user_ids(
        self,
        target_user_id: str | None,
        all_users: bool,
        *,
        require_active_device: bool,
    ) -> list[str]:
        if not target_user_id and not all_users:
            raise ValueError("Specify user_id or explicitly set all_users=true")

        params: list[Any] = []
        user_filter = ""
        if target_user_id:
            user_filter = "AND p.user_id = %s"
            params.append(target_user_id)

        device_filter = ""
        if require_active_device:
            device_filter = """
                AND EXISTS (
                    SELECT 1
                    FROM public.push_devices d
                    WHERE d.user_id = p.user_id
                      AND d.enabled = TRUE
                      AND d.sns_endpoint_arn IS NOT NULL
                )
            """

        query = f"""
            SELECT DISTINCT p.user_id
            FROM public.portfolio_items p
            WHERE (p.status IS NULL OR p.status <> 'exited')
              AND COALESCE(p.shares, 0) > 0
              {user_filter}
              {device_filter}
            ORDER BY p.user_id
        """
        with self.connection.cursor() as cursor:
            cursor.execute(query, tuple(params))
            return [row[0] for row in cursor.fetchall()]

    def holdings_for_user(self, user_id: str) -> list[dict[str, Any]]:
        query = """
            SELECT TRIM(symbol) AS symbol,
                   SUM(COALESCE(shares, 0))::bigint AS total_shares
            FROM public.portfolio_items
            WHERE user_id = %s
              AND (status IS NULL OR status <> 'exited')
              AND COALESCE(shares, 0) > 0
            GROUP BY TRIM(symbol)
            ORDER BY TRIM(symbol)
        """
        with self.connection.cursor(cursor_factory=RealDictCursor) as cursor:
            cursor.execute(query, (user_id,))
            return [dict(row) for row in cursor.fetchall()]

    def market_rows_for_date(self, demo_date: str) -> list[dict[str, Any]]:
        # Raw market dates are stored as compact text (for example 20250714).
        # Normalize the requested ISO date to that exact source representation.
        compact_date = demo_date.replace("-", "")
        query = """
            SELECT TRIM("股票代號") AS symbol,
                   TRIM("股票名稱") AS stock_name,
                   "收盤價" AS close_price,
                   "漲幅(%%)" AS change_percent
            FROM raw.raw_01_price_valuation_2025
            WHERE TRIM("日期") = %s
        """
        with self.connection.cursor(cursor_factory=RealDictCursor) as cursor:
            cursor.execute(query, (compact_date,))
            return [dict(row) for row in cursor.fetchall()]

    def active_devices_for_user(self, user_id: str) -> list[dict[str, Any]]:
        query = """
            SELECT id, environment, sns_endpoint_arn
            FROM public.push_devices
            WHERE user_id = %s
              AND enabled = TRUE
              AND sns_endpoint_arn IS NOT NULL
            ORDER BY last_registered_at DESC
        """
        with self.connection.cursor(cursor_factory=RealDictCursor) as cursor:
            cursor.execute(query, (user_id,))
            return [dict(row) for row in cursor.fetchall()]

    def disable_device(self, device_id: str) -> None:
        with self.connection.cursor() as cursor:
            cursor.execute(
                "UPDATE public.push_devices SET enabled = FALSE, updated_at = NOW() WHERE id = %s",
                (device_id,),
            )
