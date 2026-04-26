"""
Fabio Backend — FastAPI Application Entrypoint (fixed)
======================================================
Changes from original:
  • Added WebSocket /ws/liveness route
  • Added GET /api/admin/dashboard endpoint
  • Added GET /api/transactions/logs (admin)
"""

from __future__ import annotations

from contextlib import asynccontextmanager
from decimal import Decimal

from fastapi import Depends, FastAPI
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.database import get_db, init_db
from app.models import Transaction, TransactionStatus, User, UserRole
from app.routers import auth, bank, face, transactions, beneficiary, profile
from app.routers import admin as admin_router
from app.routers import analytics, qr, requests as requests_router
from app.routers.websocket_liveness import router as ws_router
from app.auth import require_role


# ── Lifespan ──────────────────────────────────────────────────────────────────
@asynccontextmanager
async def lifespan(app: FastAPI):
    try:
        await init_db()
        print("Database tables initialized.")
    except Exception as e:
        print(f"CRITICAL: Database initialization failed: {e}")
        app.state.db_error = str(e)

    try:
        import sys, os
        root_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        if root_dir not in sys.path:
            sys.path.append(root_dir)
        from seed_admin import seed_admin
        await seed_admin()
    except Exception as e:
        print(f"Admin seeding skipped: {e}")

    yield


# ── App ───────────────────────────────────────────────────────────────────────
app = FastAPI(
    title=settings.APP_NAME,
    description="FinTech API with Biometric Face Verification and Liveness Detection.",
    version="2.0.0",
    lifespan=lifespan,
)

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
app.include_router(beneficiary.router)
app.include_router(profile.router)
app.include_router(admin_router.router)
app.include_router(analytics.router)
app.include_router(qr.router)
app.include_router(requests_router.router)

# ── WebSocket ─────────────────────────────────────────────────────────────────
app.include_router(ws_router)


# ── Health ────────────────────────────────────────────────────────────────────
@app.get("/api/health", tags=["Health"])
async def health_check():
    if hasattr(app.state, "db_error"):
        return {"status": "error", "message": "Database Connection Failed",
                "error": app.state.db_error}
    return {"status": "ok", "app": settings.APP_NAME, "version": "2.0.0"}


# ── Admin dashboard stats ─────────────────────────────────────────────────────
@app.get(
    "/api/admin/dashboard",
    tags=["Admin"],
    summary="Admin dashboard statistics",
    dependencies=[Depends(require_role(UserRole.ADMIN))],
)
async def admin_dashboard(db: AsyncSession = Depends(get_db)):
    total_users  = (await db.execute(select(func.count(User.id)))).scalar() or 0
    active_users = (await db.execute(
        select(func.count(User.id)).where(User.is_active == True)
    )).scalar() or 0
    total_txns   = (await db.execute(select(func.count(Transaction.id)))).scalar() or 0
    success_txns = (await db.execute(
        select(func.count(Transaction.id)).where(
            Transaction.status == TransactionStatus.SUCCESS)
    )).scalar() or 0
    failed_txns  = (await db.execute(
        select(func.count(Transaction.id)).where(
            Transaction.status == TransactionStatus.FAILED)
    )).scalar() or 0
    pending_txns = (await db.execute(
        select(func.count(Transaction.id)).where(
            Transaction.status == TransactionStatus.PENDING)
    )).scalar() or 0
    volume_row   = await db.execute(
        select(func.coalesce(func.sum(Transaction.amount), Decimal("0"))).where(
            Transaction.status == TransactionStatus.SUCCESS)
    )
    total_volume = float(volume_row.scalar() or 0)

    return {
        "total_users":            total_users,
        "active_users":           active_users,
        "total_transactions":     total_txns,
        "successful_transactions": success_txns,
        "failed_transactions":    failed_txns,
        "pending_transactions":   pending_txns,
        "total_volume":           total_volume,
        "active_sessions":        0,  # JWT is stateless — no server-side sessions
    }


# ── Admin transaction log (used by web portal) ────────────────────────────────
@app.get(
    "/api/transactions/logs",
    tags=["Admin"],
    summary="All transactions (admin)",
    dependencies=[Depends(require_role(UserRole.ADMIN))],
)
async def admin_transaction_logs(db: AsyncSession = Depends(get_db)):
    result = await db.execute(
        select(Transaction).order_by(Transaction.created_at.desc()).limit(500)
    )
    txns = result.scalars().all()
    return [
        {
            "id":                   str(t.id),
            "amount":               str(t.amount),
            "currency":             t.currency,
            "status":               t.status.value,
            "auth_method":          t.auth_method.value,
            "from_account_id":      str(t.from_account_id) if t.from_account_id else None,
            "to_account_identifier": t.to_account_identifier,
            "description":          t.description,
            "created_at":           t.created_at.isoformat(),
        }
        for t in txns
    ]
