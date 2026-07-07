import secrets
from typing import Optional

from fastapi import Header, HTTPException, status

from app.core.config import settings
from app.core.security import TokenVerificationError, decode_session_token


async def get_current_user_id(
    authorization: Optional[str] = Header(default=None),
    x_user_id: Optional[str] = Header(default=None),
) -> str:
    """Resolve the acting user.

    Preferred path: `Authorization: Bearer <session JWT>` issued by /auth/*.
    Transition path: the legacy unauthenticated X-User-Id header, accepted only
    while ALLOW_LEGACY_HEADER_AUTH is on so already-shipped clients keep working.
    """
    if authorization:
        scheme, _, token = authorization.partition(" ")
        if scheme.lower() != "bearer" or not token.strip():
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="登入憑證格式錯誤，請重新登入"
            )
        try:
            return decode_session_token(token.strip())
        except TokenVerificationError:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="登入憑證無效或已過期，請重新登入"
            )

    if settings.ALLOW_LEGACY_HEADER_AUTH:
        user_id = (x_user_id or "").strip()
        # "demo-user" keeps pre-account data reachable for legacy clients / guests
        return user_id if user_id else "demo-user"

    raise HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="請先登入"
    )


async def verify_admin_key(x_admin_key: str = Header(...)):
    """Verify admin API key from request header. Disabled until a key is provisioned."""
    if not settings.ADMIN_API_KEY:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Admin API is not configured"
        )
    if not secrets.compare_digest(x_admin_key, settings.ADMIN_API_KEY):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Invalid admin API key"
        )
