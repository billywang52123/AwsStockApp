"""DynamoDB-backed idempotency for SNS device deliveries."""

from __future__ import annotations

import os
import time
from typing import Any

import boto3
from botocore.exceptions import ClientError


class DeliveryDeduplicator:
    def __init__(self, client: Any | None = None):
        self.table_name = os.environ["DEDUP_TABLE_NAME"]
        self.client = client or boto3.client(
            "dynamodb", region_name=os.getenv("AWS_REGION", "us-east-1")
        )

    @staticmethod
    def key(*, demo_date: str, user_id: str, symbol: str, device_id: str) -> str:
        return f"{demo_date}#{user_id}#{symbol}#{device_id}"

    def claim(self, dedupe_key: str) -> bool:
        now = int(time.time())
        try:
            self.client.put_item(
                TableName=self.table_name,
                Item={
                    "dedupe_key": {"S": dedupe_key},
                    "status": {"S": "PROCESSING"},
                    "created_at": {"N": str(now)},
                    "expires_at": {"N": str(now + 30 * 24 * 60 * 60)},
                },
                ConditionExpression="attribute_not_exists(dedupe_key)",
            )
            return True
        except ClientError as error:
            if error.response.get("Error", {}).get("Code") == "ConditionalCheckFailedException":
                return False
            raise

    def mark_sent(self, dedupe_key: str, message_id: str) -> None:
        self.client.update_item(
            TableName=self.table_name,
            Key={"dedupe_key": {"S": dedupe_key}},
            UpdateExpression="SET #status = :status, message_id = :message_id, sent_at = :sent_at",
            ExpressionAttributeNames={"#status": "status"},
            ExpressionAttributeValues={
                ":status": {"S": "SENT"},
                ":message_id": {"S": message_id},
                ":sent_at": {"N": str(int(time.time()))},
            },
        )

    def release(self, dedupe_key: str) -> None:
        """Release a claim after a confirmed provider-side API failure."""
        self.client.delete_item(
            TableName=self.table_name,
            Key={"dedupe_key": {"S": dedupe_key}},
        )
