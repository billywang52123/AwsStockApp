from datetime import datetime, timezone

from sqlalchemy import and_, select
from sqlalchemy.orm import Session

from app.models.push_device import PushDevice, token_hash
from app.services.sns_push_service import SnsPushService


def _now() -> datetime:
    return datetime.now(timezone.utc)


class PushDeviceService:
    def __init__(self, db: Session, sns: SnsPushService | None = None):
        self.db = db
        self.sns = sns or SnsPushService()

    @staticmethod
    def serialize(device: PushDevice) -> dict:
        return {
            "id": device.id,
            "platform": device.platform,
            "environment": device.environment,
            "enabled": device.enabled,
            "registration_status": (
                "active" if device.sns_endpoint_arn else "pending_sns_configuration"
            ),
            "last_registered_at": device.last_registered_at,
        }

    def register(
        self, *, user_id: str, device_token: str, platform: str, environment: str
    ) -> dict:
        digest = token_hash(device_token)
        device = self.db.scalars(
            select(PushDevice).where(
                and_(
                    PushDevice.environment == environment,
                    PushDevice.device_token_hash == digest,
                )
            )
        ).first()

        now = _now()
        if device is None:
            device = PushDevice(
                user_id=user_id,
                platform=platform,
                environment=environment,
                device_token=device_token,
                device_token_hash=digest,
                enabled=True,
                last_registered_at=now,
                updated_at=now,
            )
            self.db.add(device)
            self.db.flush()
        else:
            # The physical device may sign out and later belong to another user.
            device.user_id = user_id
            device.platform = platform
            device.device_token = device_token
            device.enabled = True
            device.last_registered_at = now
            device.updated_at = now

        endpoint_arn = self.sns.ensure_endpoint(
            device_token=device_token,
            environment=environment,
            user_id=user_id,
            existing_endpoint_arn=device.sns_endpoint_arn,
        )
        if endpoint_arn:
            device.sns_endpoint_arn = endpoint_arn
        self.db.flush()
        return self.serialize(device)

    def list_for_user(self, user_id: str) -> list[dict]:
        devices = self.db.scalars(
            select(PushDevice)
            .where(PushDevice.user_id == user_id)
            .order_by(PushDevice.last_registered_at.desc())
        ).all()
        return [self.serialize(device) for device in devices]

    def send_to_user(
        self, user_id: str, *, title: str, body: str, data: dict | None = None
    ) -> int:
        """Push to every enabled, SNS-registered device of the user.

        Returns the number of devices the message was handed to SNS for.
        Dead endpoints (app uninstalled) are disabled instead of retried.
        """
        devices = self.db.scalars(
            select(PushDevice).where(
                and_(PushDevice.user_id == user_id, PushDevice.enabled.is_(True))
            )
        ).all()
        sent = 0
        for device in devices:
            if not device.sns_endpoint_arn:
                continue
            outcome = self.sns.publish(
                device.sns_endpoint_arn, title=title, body=body, data=data
            )
            if outcome == "sent":
                sent += 1
            elif outcome == "disabled":
                device.enabled = False
                device.updated_at = _now()
        self.db.flush()
        return sent

    def delete(self, *, user_id: str, device_id: str) -> bool:
        device = self.db.scalars(
            select(PushDevice).where(
                and_(PushDevice.id == device_id, PushDevice.user_id == user_id)
            )
        ).first()
        if device is None:
            return False
        self.sns.delete_endpoint(device.sns_endpoint_arn)
        self.db.delete(device)
        self.db.flush()
        return True

