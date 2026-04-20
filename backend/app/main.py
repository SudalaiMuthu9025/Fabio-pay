"""
Fabio Backend — FastAPI Application Entrypoint
================================================
REST API with JWT auth, face verification, bank accounts, and transactions.
"""

from __future__ import annotations

from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.config import settings
from app.database import init_db
from app.routers import auth, bank, face, transactions


# ── Lifespan ──────────────────────────────────────────────────────────────────
@asynccontextmanager
async def lifespan(app: FastAPI):
    """Run once on startup: create DB tables if they don't exist."""
    await init_db()

    # Auto-seed admin user
    try:
        import sys
        import os
        root_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        if root_dir not in sys.path:
            sys.path.append(root_dir)
        from seed_admin import seed_admin
        await seed_admin()
        print("Admin seeding completed.")
    except Exception as e:
        print(f"Admin seeding skipped: {e}")

    yield


# ── App Instance ──────────────────────────────────────────────────────────────
app = FastAPI(
    title=settings.APP_NAME,
    description=(
        "FinTech API with Biometric Face Verification, "
        "JWT Auth, and Simon Says Liveness Detection."
    ),
    version="2.0.0",
    lifespan=lifespan,
)

# ── CORS ──────────────────────────────────────────────────────────────────────
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.ALLOWED_ORIGINS.split(","),
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ── REST Routers ──────────────────────────────────────────────────────────────
app.include_router(auth.router)
app.include_router(face.router)
app.include_router(bank.router)
app.include_router(transactions.router)


# ── Health Check ──────────────────────────────────────────────────────────────
@app.get("/api/health", tags=["Health"])
async def health_check():
    return {"status": "ok", "app": settings.APP_NAME, "version": "2.0.0"}
