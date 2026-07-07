from typing import Optional

from pydantic_settings import BaseSettings, SettingsConfigDict

class Settings(BaseSettings):
    model_config = SettingsConfigDict(case_sensitive=True)

    API_V1_STR: str = "/api"
    PROJECT_NAME: str = "StockMood API"
    DATABASE_URL: str = "sqlite:///./stock_mood.db"
    # No default on purpose: admin import endpoints stay disabled until a key is provisioned.
    ADMIN_API_KEY: Optional[str] = None
    ALLOWED_ORIGINS: str = "http://localhost:3000,http://localhost:8080"
    OPENAI_API_KEY: str = ""

    # --- Auth / session tokens ---
    # HS256 secret for the session JWTs we issue. Empty = random per-process
    # secret (dev only; every restart logs everyone out). Set in production.
    JWT_SECRET: str = ""
    JWT_EXPIRE_DAYS: int = 90
    # Expected audiences when verifying sign-in tokens from Apple / Google.
    APPLE_BUNDLE_ID: str = "Wbilly.StockMoodApp"
    GOOGLE_CLIENT_ID: str = "155358777599-a0lp1l2leen45l2ak9h5p76bmlfiqtfo.apps.googleusercontent.com"
    # Transition switch: accept the legacy unauthenticated X-User-Id header.
    # Flip to False once all shipped clients send Bearer tokens.
    ALLOW_LEGACY_HEADER_AUTH: bool = True

settings = Settings()
