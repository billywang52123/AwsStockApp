"""Sign-in endpoints: exchange a verified identity for our own session JWT.

The iOS app calls one of these right after Apple / Google / guest sign-in and
then sends the returned access_token as `Authorization: Bearer …`.
"""

import logging
import re
import uuid
from typing import Optional

from fastapi import APIRouter, HTTPException, status
from pydantic import BaseModel

from app.core.security import (
    TokenVerificationError,
    create_session_token,
    verify_apple_identity_token,
    verify_google_id_token,
)
from app.schemas.common_schema import ApiResponse

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/auth", tags=["Auth"])

# Matches the ids the app has always generated locally: "guest-<UUID>"
GUEST_ID_PATTERN = re.compile(r"^guest-[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$")


class AppleAuthRequest(BaseModel):
    identity_token: str
    user_id: Optional[str] = None
    full_name: Optional[str] = None
    email: Optional[str] = None


class GoogleAuthRequest(BaseModel):
    id_token: str
    email: Optional[str] = None
    name: Optional[str] = None


class GuestAuthRequest(BaseModel):
    # Existing installs send their locally generated guest id so their data
    # stays reachable; new installs omit it and get a server-generated one.
    guest_id: Optional[str] = None


def _session_response(user_id: str) -> ApiResponse[dict]:
    return ApiResponse(
        success=True,
        data={
            "access_token": create_session_token(user_id),
            "token_type": "bearer",
            "user_id": user_id,
        },
    )


@router.post("/apple", response_model=ApiResponse[dict])
async def sign_in_with_apple(body: AppleAuthRequest):
    try:
        claims = verify_apple_identity_token(body.identity_token)
    except TokenVerificationError as e:
        logger.warning("Apple sign-in rejected: %s", e)
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Apple 登入驗證失敗，請重新登入"
        )
    # claims["sub"] is the same stable id the app sees as credential.user
    return _session_response(f"apple-{claims['sub']}")


@router.post("/google", response_model=ApiResponse[dict])
async def sign_in_with_google(body: GoogleAuthRequest):
    try:
        claims = verify_google_id_token(body.id_token)
    except TokenVerificationError as e:
        logger.warning("Google sign-in rejected: %s", e)
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Google 登入驗證失敗，請重新登入"
        )
    return _session_response(f"google-{claims['sub']}")


@router.post("/guest", response_model=ApiResponse[dict])
async def sign_in_as_guest(body: GuestAuthRequest):
    if body.guest_id:
        if not GUEST_ID_PATTERN.match(body.guest_id):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="訪客身分格式錯誤"
            )
        user_id = body.guest_id
    else:
        user_id = f"guest-{uuid.uuid4()}"
    return _session_response(user_id)
