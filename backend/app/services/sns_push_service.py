import logging
import re
from typing import Optional

import boto3
from botocore.exceptions import ClientError

from app.core.config import settings

logger = logging.getLogger(__name__)


class SnsPushService:
    def __init__(self, client=None):
        self._client = client

    @property
    def client(self):
        if self._client is None:
            self._client = boto3.client("sns", region_name=settings.AWS_REGION)
        return self._client

    @staticmethod
    def platform_application_arn(environment: str) -> Optional[str]:
        if environment == "production":
            return settings.SNS_APNS_PLATFORM_APPLICATION_ARN or None
        return settings.SNS_APNS_SANDBOX_PLATFORM_APPLICATION_ARN or None

    def ensure_endpoint(
        self,
        *,
        device_token: str,
        environment: str,
        user_id: str,
        existing_endpoint_arn: Optional[str] = None,
    ) -> Optional[str]:
        """Create or refresh an SNS mobile endpoint.

        Returning None is intentional when SNS has not been configured yet: the
        token remains safely registered in RDS and can be synchronized later.
        """
        platform_arn = self.platform_application_arn(environment)
        if not platform_arn:
            return None

        if existing_endpoint_arn:
            try:
                self.client.set_endpoint_attributes(
                    EndpointArn=existing_endpoint_arn,
                    Attributes={
                        "Token": device_token,
                        "Enabled": "true",
                        "CustomUserData": user_id,
                    },
                )
                return existing_endpoint_arn
            except ClientError:
                logger.warning("SNS endpoint refresh failed; recreating endpoint", exc_info=True)

        try:
            response = self.client.create_platform_endpoint(
                PlatformApplicationArn=platform_arn,
                Token=device_token,
                CustomUserData=user_id,
            )
            endpoint_arn = response["EndpointArn"]
        except ClientError as exc:
            # SNS reports an existing token with different attributes as an
            # InvalidParameter error and includes the reusable EndpointArn.
            message = exc.response.get("Error", {}).get("Message", "")
            match = re.search(r"Endpoint (arn:[^ ]+) already exists", message)
            if not match:
                raise
            endpoint_arn = match.group(1)
        self.client.set_endpoint_attributes(
            EndpointArn=endpoint_arn,
            Attributes={
                "Token": device_token,
                "Enabled": "true",
                "CustomUserData": user_id,
            },
        )
        return endpoint_arn

    def delete_endpoint(self, endpoint_arn: Optional[str]) -> None:
        if endpoint_arn:
            self.client.delete_endpoint(EndpointArn=endpoint_arn)
