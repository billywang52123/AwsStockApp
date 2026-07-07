from typing import Optional

from fastapi import Header, HTTPException, status
from app.core.config import settings


async def get_current_user_id(x_user_id: Optional[str] = Header(default=None)) -> str:
    """Resolve the acting user from the X-User-Id header sent by the iOS app.

    Falls back to "demo-user" for legacy clients / guests that don't send one,
    so old data stays reachable instead of disappearing after upgrade.
    """
    user_id = (x_user_id or "").strip()
    return user_id if user_id else "demo-user"


async def verify_admin_key(x_admin_key: str = Header(...)):
    """Verify admin API key from request header."""
    if x_admin_key != settings.ADMIN_API_KEY:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Invalid admin API key"
        )
