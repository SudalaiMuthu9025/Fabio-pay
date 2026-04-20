"""
Fabio Backend — Application Configuration
==========================================
Loads settings from environment variables (or .env file).
"""

from pydantic import model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

class Settings(BaseSettings):
    """Central configuration loaded from environment / .env file."""

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=False,
    )

    # ── Database ──────────────────────────────────────────────────────────
    DATABASE_URL: str = (
        "postgresql+asyncpg://fabio:fabio@localhost:5432/fabio_db"
    )

    # ── JWT Auth ─────────────────────────────────────────────────────────
    SECRET_KEY: str = "CHANGE-ME-in-production-use-openssl-rand-hex-32"
    JWT_ALGORITHM: str = "HS256"
    JWT_EXPIRE_MINUTES: int = 1440  # 24 hours

    # ── Transaction ──────────────────────────────────────────────────────
    TRANSACTION_THRESHOLD: float = 5000.00  # ₹5000 default

    # ── Face Verification ────────────────────────────────────────────────
    FACE_MATCH_THRESHOLD: float = 0.35  # cosine distance threshold

    # ── General ───────────────────────────────────────────────────────────
    APP_NAME: str = "Fabio"
    DEBUG: bool = True
    ALLOWED_ORIGINS: str = "*"

    @model_validator(mode="after")
    def fix_db_url(self) -> 'Settings':
        if self.DATABASE_URL and self.DATABASE_URL.startswith("postgresql://"):
            self.DATABASE_URL = self.DATABASE_URL.replace(
                "postgresql://", "postgresql+asyncpg://", 1
            )
        return self

settings = Settings()
