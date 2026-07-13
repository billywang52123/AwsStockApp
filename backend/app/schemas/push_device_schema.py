from datetime import datetime
from typing import Literal

from pydantic import BaseModel, Field, field_validator


class PushDeviceRegister(BaseModel):
    device_token: str = Field(min_length=32, max_length=512)
    platform: Literal["ios"] = "ios"
    environment: Literal["sandbox", "production"] = "sandbox"

    @field_validator("device_token")
    @classmethod
    def normalize_device_token(cls, value: str) -> str:
        # Accept the common Xcode formats: raw hex or "<ab cd ...>".
        normalized = value.strip().replace("<", "").replace(">", "").replace(" ", "")
        if not normalized:
            raise ValueError("device_token is required")
        return normalized


class PushDeviceRead(BaseModel):
    id: str
    platform: str
    environment: str
    enabled: bool
    registration_status: str
    last_registered_at: datetime

