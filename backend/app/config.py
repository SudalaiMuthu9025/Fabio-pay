"""
Fabio Backend — Application Configuration (fixed)
==================================================
Key fixes vs original:
  • JWT_EXPIRE_MINUTES kept consistent (was referenced both ways)
  • Added SESSION_EXPIRE_HOURS (used in .env.example)
  • Added EAR_THRESHOLD, MAR_THRESHOLD, CHALLENGE_COUNT (liveness engine)
  • PANIC_TIMER_SECONDS kept
  • TRANSACTION_THRESHOLD kept
"""

from pydantic import model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=False,
    )

    # ── Database ──────────────────────────────────────────────────────────
    DATABASE_URL: str = (
        "postgresql://postgres:fCApGafpzgDHKuTAnWkolWhoyFkfOBiG@postgres.railway.internal:5432/railway"
    )

    # ── JWT Auth ─────────────────────────────────────────────────────────
    SECRET_KEY: str = "CHANGE-ME-in-production-use-openssl-rand-hex-32"
    JWT_ALGORITHM: str = "HS256"
    JWT_EXPIRE_MINUTES: int = 1440          # 24 hours
    SESSION_EXPIRE_HOURS: int = 24          # alias used by .env.example

    # ── Transaction security ──────────────────────────────────────────────
    TRANSACTION_THRESHOLD: float = 5000.00  # ₹5 000 triggers liveness

    # ── Face verification ─────────────────────────────────────────────────
    FACE_MATCH_THRESHOLD: float = 0.35      # cosine distance

    # ── Liveness challenge ────────────────────────────────────────────────
    EAR_THRESHOLD: float = 0.20             # eye aspect ratio → blink
    MAR_THRESHOLD: float = 0.50             # mouth aspect ratio → smile
    CHALLENGE_COUNT: int = 3               # actions per challenge
    PANIC_TIMER_SECONDS: int = 15          # total window per challenge

    # ── General ───────────────────────────────────────────────────────────
    APP_NAME: str = "Fabio"
    DEBUG: bool = True
    ALLOWED_ORIGINS: str = "*"

    @model_validator(mode="after")
    def fix_db_url(self) -> "Settings":
        if self.DATABASE_URL:
            if self.DATABASE_URL.startswith("postgres://"):
                self.DATABASE_URL = self.DATABASE_URL.replace(
                    "postgres://", "postgresql+asyncpg://", 1
                )
            elif self.DATABASE_URL.startswith("postgresql://"):
                self.DATABASE_URL = self.DATABASE_URL.replace(
                    "postgresql://", "postgresql+asyncpg://", 1
                )
        return self


settings = Settings()
