"""Session-token issuance and third-party identity-token verification.

Two token worlds meet here:
1. Sign-in tokens from Apple / Google (RS256, verified against their public JWKS).
2. Our own session JWTs (HS256), issued after a sign-in token checks out and
   sent back by the app as `Authorization: Bearer <token>` on every request.
"""

import logging
import secrets
from datetime import datetime, timedelta, timezone

import jwt
from jwt import PyJWKClient

from app.core.config import settings

logger = logging.getLogger(__name__)

SESSION_ALGORITHM = "HS256"

if settings.JWT_SECRET:
    _jwt_secret = settings.JWT_SECRET
else:
    _jwt_secret = secrets.token_urlsafe(48)
    logger.warning(
        "JWT_SECRET is not set — using a random per-process secret. "
        "All sessions are invalidated on restart; set JWT_SECRET in production."
    )

APPLE_JWKS_URL = "https://appleid.apple.com/auth/keys"
APPLE_ISSUER = "https://appleid.apple.com"
GOOGLE_JWKS_URL = "https://www.googleapis.com/oauth2/v3/certs"
GOOGLE_ISSUERS = ("https://accounts.google.com", "accounts.google.com")

# Lazy clients: no network traffic until the first verification request.
_apple_jwk_client = PyJWKClient(APPLE_JWKS_URL)
_google_jwk_client = PyJWKClient(GOOGLE_JWKS_URL)


class TokenVerificationError(Exception):
    """A sign-in or session token failed verification."""


# --- Our session JWTs -------------------------------------------------------

def create_session_token(user_id: str) -> str:
    now = datetime.now(timezone.utc)
    payload = {
        "sub": user_id,
        "iat": now,
        "exp": now + timedelta(days=settings.JWT_EXPIRE_DAYS),
    }
    return jwt.encode(payload, _jwt_secret, algorithm=SESSION_ALGORITHM)


def decode_session_token(token: str) -> str:
    """Return the user id inside a session token, or raise TokenVerificationError."""
    try:
        payload = jwt.decode(token, _jwt_secret, algorithms=[SESSION_ALGORITHM])
    except jwt.PyJWTError as e:
        raise TokenVerificationError(f"invalid session token: {e}") from e
    user_id = payload.get("sub")
    if not user_id:
        raise TokenVerificationError("session token has no subject")
    return user_id


# --- Apple / Google sign-in tokens ------------------------------------------

def _verify_with_jwks(token: str, jwk_client: PyJWKClient, audience: str, issuer_check) -> dict:
    try:
        signing_key = jwk_client.get_signing_key_from_jwt(token)
        claims = jwt.decode(
            token,
            signing_key.key,
            algorithms=["RS256"],
            audience=audience or None,
            options={"verify_aud": bool(audience)},
        )
    except jwt.PyJWTError as e:
        raise TokenVerificationError(f"identity token rejected: {e}") from e
    if not issuer_check(claims.get("iss", "")):
        raise TokenVerificationError(f"unexpected issuer: {claims.get('iss')}")
    if not claims.get("sub"):
        raise TokenVerificationError("identity token has no subject")
    return claims


def verify_apple_identity_token(identity_token: str) -> dict:
    """Verify an Apple Sign-In identityToken and return its claims."""
    return _verify_with_jwks(
        identity_token,
        _apple_jwk_client,
        audience=settings.APPLE_BUNDLE_ID,
        issuer_check=lambda iss: iss == APPLE_ISSUER,
    )


def verify_google_id_token(id_token: str) -> dict:
    """Verify a Google Sign-In id_token and return its claims."""
    return _verify_with_jwks(
        id_token,
        _google_jwk_client,
        audience=settings.GOOGLE_CLIENT_ID,
        issuer_check=lambda iss: iss in GOOGLE_ISSUERS,
    )
