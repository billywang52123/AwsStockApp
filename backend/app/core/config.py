from pydantic_settings import BaseSettings, SettingsConfigDict

class Settings(BaseSettings):
    model_config = SettingsConfigDict(case_sensitive=True)
    
    API_V1_STR: str = "/api"
    PROJECT_NAME: str = "StockMood API"
    DATABASE_URL: str = "sqlite:///./stock_mood.db"
    ADMIN_API_KEY: str = "stockmood-admin-secret-key"
    ALLOWED_ORIGINS: str = "http://localhost:3000,http://localhost:8080"
    OPENAI_API_KEY: str = ""

settings = Settings()
