"""SNS mobile-push payload construction and delivery."""

from __future__ import annotations

import json
import os
from typing import Any

import boto3
from botocore.exceptions import ClientError

from bedrock_content_service import PushContent
from candidate_service import PushCandidate


class SnsPublisher:
    def __init__(self, client: Any | None = None):
        self.client = client or boto3.client(
            "sns", region_name=os.getenv("AWS_REGION", "us-east-1")
        )

    def publish(
        self,
        *,
        endpoint_arn: str,
        candidate: PushCandidate,
        content: PushContent,
    ) -> str:
        platform_key = self._platform_key(endpoint_arn)
        apns_payload = {
            "aps": {
                "alert": {"title": content.title, "body": content.body},
                "sound": "default",
                "thread-id": "holding-signal",
            },
            "schema_version": 1,
            "type": "holding_signal",
            "route": "stock_detail",
            "symbol": candidate.symbol,
            "demo_date": candidate.demo_date,
        }
        message = {
            "default": content.body,
            platform_key: json.dumps(apns_payload, ensure_ascii=False, separators=(",", ":")),
        }
        response = self.client.publish(
            TargetArn=endpoint_arn,
            Message=json.dumps(message, ensure_ascii=False, separators=(",", ":")),
            MessageStructure="json",
        )
        return response["MessageId"]

    @staticmethod
    def _platform_key(endpoint_arn: str) -> str:
        if "/APNS_SANDBOX/" in endpoint_arn:
            return "APNS_SANDBOX"
        if "/APNS/" in endpoint_arn:
            return "APNS"
        raise ValueError("Only APNS and APNS_SANDBOX SNS endpoints are supported")

    @staticmethod
    def is_disabled_endpoint(error: ClientError) -> bool:
        return error.response.get("Error", {}).get("Code") in {
            "EndpointDisabled",
            "NotFound",
        }
