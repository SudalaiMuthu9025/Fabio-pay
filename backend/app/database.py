"""
Fabio Backend — Database Connection & Session Management
=========================================================
Async SQLAlchemy engine + session factory for FastAPI dependency injection.
"""

from sqlalchemy.ext.asyncio import (
    AsyncSession,
    async_sessionmaker,
    create_async_engine,
)
from sqlalchemy.orm import DeclarativeBase

from app.config import settings

# ── Async Engine ──────────────────────────────────────────────────────────────
# pool_pre_ping keeps connections healthy; echo=True logs SQL in dev mode.
engine = create_async_engine(
    settings.DATABASE_URL,
    echo=settings.DEBUG,
    pool_pre_ping=True,
    pool_size=10,
    max_overflow=20,
)

# ── Session Factory ───────────────────────────────────────────────────────────
async_session_factory = async_sessionmaker(
    bind=engine,
    class_=AsyncSession,
    expire_on_commit=False,
)


# ── Declarative Base ─────────────────────────────────────────────────────────
class Base(DeclarativeBase):
    """Base class for all ORM models."""
    pass


# ── FastAPI Dependency ────────────────────────────────────────────────────────
async def get_db() -> AsyncSession:  # type: ignore[misc]
    """
    Yield an async database session.

    Usage in FastAPI:
        @router.get("/items")
        async def read_items(db: AsyncSession = Depends(get_db)):
            ...
    """
    async with async_session_factory() as session:
        try:
            yield session
            await session.commit()
        except Exception:
            await session.rollback()
            raise


# ── Table Creation Helper ─────────────────────────────────────────────────────
async def init_db() -> None:
    """Create all tables that don't yet exist, and migrate missing columns."""
    async with engine.begin() as conn:
        # 1. Create any brand-new tables
        await conn.run_sync(Base.metadata.create_all)

        # 2. Migrate: add columns that were added to models after initial deploy.
        #    ALTER TABLE … ADD COLUMN IF NOT EXISTS is PostgreSQL ≥ 9.6.
        migrations = [
            """ALTER TABLE users
               ADD COLUMN IF NOT EXISTS daily_transfer_limit
               NUMERIC(15,2) NOT NULL DEFAULT 100000.00""",
            """ALTER TABLE users
               ADD COLUMN IF NOT EXISTS monthly_transfer_limit
               NUMERIC(15,2) NOT NULL DEFAULT 1000000.00""",
            """ALTER TABLE users
               ADD COLUMN IF NOT EXISTS biometric_login_enabled
               BOOLEAN NOT NULL DEFAULT FALSE""",
        ]
        from sqlalchemy import text
        for sql in migrations:
            await conn.execute(text(sql))

    print("Database tables ready (migrations applied).")
