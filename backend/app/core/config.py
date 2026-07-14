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

    # --- AWS / Bedrock ---
    AWS_REGION: str = "us-east-1"
    # us-east-1 需先在 Bedrock console 開通此模型存取權。
    # 用跨區 inference profile 形式(us. 前綴)。注意 Bedrock 模型會 EOL,
    # 過期會回 ResourceNotFoundException("model version has reached end of life"),
    # 屆時改成當時可用的視覺模型即可(可用 env BEDROCK_VISION_MODEL_ID 覆寫)。
    # 2026-07-12:claude-haiku-4-5 這支模型在本帳號回 AccessDeniedException
    # (AWS Marketplace 訂閱檢查失敗,即使用完整權限的 IAM 使用者呼叫也一樣,
    # 與我們的 IAM 設計無關);同帳號呼叫 sonnet-4-5 正常,故先切換為此模型。
    BEDROCK_VISION_MODEL_ID: str = "us.anthropic.claude-sonnet-4-5-20250929-v1:0"
    # 若設定,啟動時由 Secrets Manager 抓 RDS 憑證組出 DATABASE_URL(見 aws_secrets.py)
    DB_SECRET_ARN: Optional[str] = None
    # SNS Mobile Push platform applications. Leave empty to persist APNs tokens
    # first and synchronize them after SNS is configured.
    SNS_APNS_SANDBOX_PLATFORM_APPLICATION_ARN: str = ""
    SNS_APNS_PLATFORM_APPLICATION_ARN: str = ""

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
