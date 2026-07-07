from fastapi import Header, HTTPException, status
from app.core.config import settings


async def verify_admin_key(x_admin_key: str = Header(...)):
    """Verify admin API key from request header."""
    if x_admin_key != settings.ADMIN_API_KEY:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Invalid admin API key"
        )
