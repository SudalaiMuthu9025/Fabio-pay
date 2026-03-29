"""
Fabio Backend — Application Configuration
==========================================
Loads settings from environment variables (or .env file).
All sensitive values default to development placeholders — override in production.
"""

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

    # ── JWT / Auth ────────────────────────────────────────────────────────
    SECRET_KEY: str = "CHANGE-ME-in-production-use-openssl-rand-hex-32"
    ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 30

    # ── Biometric Engine ──────────────────────────────────────────────────
    EAR_THRESHOLD: float = 0.2        # Eye-Aspect-Ratio below this = blink
    MAR_THRESHOLD: float = 0.5        # Mouth-Aspect-Ratio above this = smile
    CHALLENGE_COUNT: int = 3          # Number of actions in a challenge sequence
    PANIC_TIMER_SECONDS: int = 15     # Max seconds to complete all challenges

    # ── General ───────────────────────────────────────────────────────────
    APP_NAME: str = "Fabio"
    DEBUG: bool = True


settings = Settings()
