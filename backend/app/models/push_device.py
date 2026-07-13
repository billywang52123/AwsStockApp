import hashlib
import uuid
from datetime import datetime, timezone

from sqlalchemy import Boolean, DateTime, String, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from app.db.database import Base


def _now() -> datetime:
    return datetime.now(timezone.utc)


def token_hash(device_token: str) -> str:
    return hashlib.sha256(device_token.encode("utf-8")).hexdigest()


class PushDevice(Base):
    __tablename__ = "push_devices"
    __table_args__ = (
        UniqueConstraint("environment", "device_token_hash", name="uq_push_device_env_token"),
    )

    id: Mapped[str] = mapped_column(
        String, primary_key=True, default=lambda: str(uuid.uuid4())
    )
    user_id: Mapped[str] = mapped_column(String, index=True)
    platform: Mapped[str] = mapped_column(String, default="ios")
    environment: Mapped[str] = mapped_column(String, default="sandbox", index=True)
    device_token: Mapped[str] = mapped_column(String, nullable=False)
    device_token_hash: Mapped[str] = mapped_column(String, nullable=False, index=True)
    sns_endpoint_arn: Mapped[str | None] = mapped_column(String, nullable=True)
    enabled: Mapped[bool] = mapped_column(Boolean, default=True)
    last_registered_at: Mapped[datetime] = mapped_column(DateTime, default=_now)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=_now)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=_now, onupdate=_now)

