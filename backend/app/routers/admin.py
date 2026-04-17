"""
Fabio Backend — Admin Router
==============================
GET    /api/admin/dashboard            — System statistics
GET    /api/admin/users                — List all users (paginated)
PATCH  /api/admin/users/{id}/role      — Change user role
PATCH  /api/admin/users/{id}/status    — Activate/deactivate user
GET    /api/admin/audit-logs           — System-wide audit trail
GET    /api/admin/sessions             — All active sessions
DELETE /api/admin/sessions/{id}        — Force-terminate a session
"""

from __future__ import annotations

import uuid
from decimal import Decimal

from fastapi import APIRouter, Depends, HTTPException, Query, Request, status
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth import get_current_user, require_role, revoke_session_by_id
from app.database import get_db
from app.models import (
    AuditLog,
    Session,
    TransactionLog,
    TransactionStatus,
    User,
    UserRole,
)
from app.schemas import (
    AuditLogOut,
    DashboardStats,
    SessionOut,
    UserOut,
    UserRoleUpdate,
    UserStatusUpdate,
)

router = APIRouter(prefix="/api/admin", tags=["Admin"])


# ── Dashboard ─────────────────────────────────────────────────────────────────
@router.get(
    "/dashboard",
    response_model=DashboardStats,
    summary="System dashboard statistics",
    dependencies=[Depends(require_role(UserRole.ADMIN))],
)
async def dashboard(db: AsyncSession = Depends(get_db)):
    # Total users
    total_users = await db.scalar(select(func.count(User.id))) or 0
    active_users = await db.scalar(
        select(func.count(User.id)).where(User.is_active == True)
    ) or 0

    # Transactions
    total_txns = await db.scalar(select(func.count(TransactionLog.id))) or 0
    success_txns = await db.scalar(
        select(func.count(TransactionLog.id)).where(
            TransactionLog.status == TransactionStatus.SUCCESS
        )
    ) or 0
    failed_txns = await db.scalar(
        select(func.count(TransactionLog.id)).where(
            TransactionLog.status == TransactionStatus.FAILED
        )
    ) or 0
    pending_txns = await db.scalar(
        select(func.count(TransactionLog.id)).where(
            TransactionLog.status == TransactionStatus.PENDING
        )
    ) or 0

    # Active sessions
    active_sessions = await db.scalar(
        select(func.count(Session.id)).where(Session.is_active == True)
    ) or 0

    # Total transaction volume
    total_volume = await db.scalar(
        select(func.sum(TransactionLog.amount)).where(
            TransactionLog.status == TransactionStatus.SUCCESS
        )
    ) or Decimal("0.00")

    # Face-registered users
    face_registered_users = await db.scalar(
        select(func.count(User.id)).where(User.face_encoding.isnot(None))
    ) or 0

    return DashboardStats(
        total_users=total_users,
        active_users=active_users,
        total_transactions=total_txns,
        successful_transactions=success_txns,
        failed_transactions=failed_txns,
        pending_transactions=pending_txns,
        active_sessions=active_sessions,
        total_volume=total_volume,
        face_registered_users=face_registered_users,
    )


# ── List All Users ────────────────────────────────────────────────────────────
@router.get(
    "/users",
    response_model=list[UserOut],
    summary="List all users (Admin only)",
    dependencies=[Depends(require_role(UserRole.ADMIN))],
)
async def list_all_users(
    role: str | None = Query(None, description="Filter by role"),
    active: bool | None = Query(None, description="Filter by active status"),
    search: str | None = Query(None, description="Search by email or name"),
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
    db: AsyncSession = Depends(get_db),
):
    query = select(User)

    if role:
        query = query.where(User.role == role)
    if active is not None:
        query = query.where(User.is_active == active)
    if search:
        query = query.where(
            User.email.ilike(f"%{search}%") | User.full_name.ilike(f"%{search}%")
        )

    query = query.order_by(User.created_at.desc()).limit(limit).offset(offset)
    result = await db.execute(query)
    return result.scalars().all()


# ── Change User Role ─────────────────────────────────────────────────────────
@router.patch(
    "/users/{user_id}/role",
    response_model=UserOut,
    summary="Change user role (Admin only)",
    dependencies=[Depends(require_role(UserRole.ADMIN))],
)
async def change_user_role(
    user_id: uuid.UUID,
    body: UserRoleUpdate,
    request: Request,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    # Cannot change own role
    if user_id == current_user.id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Cannot change your own role",
        )

    result = await db.execute(select(User).where(User.id == user_id))
    user = result.scalar_one_or_none()
    if user is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User not found",
        )

    old_role = user.role.value
    user.role = UserRole(body.role)

    # Audit log
    audit = AuditLog(
        user_id=current_user.id,
        action="admin.change_role",
        target_type="user",
        target_id=str(user_id),
        ip_address=request.client.host if request.client else None,
        details={"old_role": old_role, "new_role": body.role},
    )
    db.add(audit)
    await db.flush()

    return user


# ── Activate/Deactivate User ─────────────────────────────────────────────────
@router.patch(
    "/users/{user_id}/status",
    response_model=UserOut,
    summary="Activate or deactivate user (Admin only)",
    dependencies=[Depends(require_role(UserRole.ADMIN))],
)
async def change_user_status(
    user_id: uuid.UUID,
    body: UserStatusUpdate,
    request: Request,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    if user_id == current_user.id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Cannot change your own status",
        )

    result = await db.execute(select(User).where(User.id == user_id))
    user = result.scalar_one_or_none()
    if user is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User not found",
        )

    user.is_active = body.is_active

    # If deactivating, revoke all sessions
    if not body.is_active:
        sessions_result = await db.execute(
            select(Session).where(
                Session.user_id == user_id, Session.is_active == True
            )
        )
        for session in sessions_result.scalars().all():
            session.is_active = False

    # Audit log
    audit = AuditLog(
        user_id=current_user.id,
        action="admin.change_status",
        target_type="user",
        target_id=str(user_id),
        ip_address=request.client.host if request.client else None,
        details={"is_active": body.is_active},
    )
    db.add(audit)
    await db.flush()

    return user


# ── Audit Logs ────────────────────────────────────────────────────────────────
@router.get(
    "/audit-logs",
    response_model=list[AuditLogOut],
    summary="System-wide audit trail (Admin only)",
    dependencies=[Depends(require_role(UserRole.ADMIN))],
)
async def list_audit_logs(
    action: str | None = Query(None, description="Filter by action type"),
    limit: int = Query(100, ge=1, le=500),
    offset: int = Query(0, ge=0),
    db: AsyncSession = Depends(get_db),
):
    query = select(AuditLog)
    if action:
        query = query.where(AuditLog.action == action)
    query = query.order_by(AuditLog.created_at.desc()).limit(limit).offset(offset)
    result = await db.execute(query)
    return result.scalars().all()


# ── All Active Sessions ──────────────────────────────────────────────────────
@router.get(
    "/sessions",
    response_model=list[SessionOut],
    summary="All active sessions (Admin only)",
    dependencies=[Depends(require_role(UserRole.ADMIN))],
)
async def list_all_sessions(
    limit: int = Query(100, ge=1, le=500),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(Session)
        .where(Session.is_active == True)
        .order_by(Session.created_at.desc())
        .limit(limit)
    )
    return result.scalars().all()


# ── Force Terminate Session ───────────────────────────────────────────────────
@router.delete(
    "/sessions/{session_id}",
    status_code=status.HTTP_200_OK,
    summary="Force-terminate a session (Admin only)",
    dependencies=[Depends(require_role(UserRole.ADMIN))],
)
async def force_terminate_session(
    session_id: str,
    request: Request,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    revoked = await revoke_session_by_id(session_id, db)
    if not revoked:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Session not found or already inactive",
        )

    # Audit log
    audit = AuditLog(
        user_id=current_user.id,
        action="admin.terminate_session",
        target_type="session",
        target_id=session_id,
        ip_address=request.client.host if request.client else None,
    )
    db.add(audit)
    await db.flush()

    return {"message": "Session terminated"}


# ── Verify Bank Account ──────────────────────────────────────────────────────
@router.put(
    "/verify-bank/{bank_id}",
    summary="Admin-verify a bank account",
    dependencies=[Depends(require_role(UserRole.ADMIN))],
)
async def verify_bank_account(
    bank_id: uuid.UUID,
    request: Request,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    from app.models import BankAccount

    result = await db.execute(select(BankAccount).where(BankAccount.id == bank_id))
    account = result.scalar_one_or_none()
    if account is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Bank account not found",
        )

    account.is_verified = True

    # Audit log
    audit = AuditLog(
        user_id=current_user.id,
        action="admin.verify_bank",
        target_type="bank_account",
        target_id=str(bank_id),
        ip_address=request.client.host if request.client else None,
        details={"account_number": account.account_number, "bank_name": account.bank_name},
    )
    db.add(audit)
    await db.flush()

    return {"message": "Bank account verified", "bank_id": str(bank_id)}


# ── Revoke All Sessions for a User ──────────────────────────────────────────
@router.delete(
    "/revoke-sessions/{user_id}",
    summary="Force-revoke ALL sessions for a specific user (Admin only)",
    dependencies=[Depends(require_role(UserRole.ADMIN))],
)
async def revoke_all_user_sessions(
    user_id: uuid.UUID,
    request: Request,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    sessions_result = await db.execute(
        select(Session).where(
            Session.user_id == user_id, Session.is_active == True
        )
    )
    sessions = sessions_result.scalars().all()

    if not sessions:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="No active sessions found for this user",
        )

    count = 0
    for session in sessions:
        session.is_active = False
        count += 1

    # Audit log
    audit = AuditLog(
        user_id=current_user.id,
        action="admin.revoke_all_sessions",
        target_type="user",
        target_id=str(user_id),
        ip_address=request.client.host if request.client else None,
        details={"revoked_count": count},
    )
    db.add(audit)
    await db.flush()

    return {"message": f"Revoked {count} session(s) for user {user_id}"}


# ── Reset User Face Data (Admin) ─────────────────────────────────────────────
@router.delete(
    "/users/{user_id}/face-data",
    summary="Reset face data for a user (Admin only)",
    dependencies=[Depends(require_role(UserRole.ADMIN))],
)
async def reset_user_face_data(
    user_id: uuid.UUID,
    request: Request,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(select(User).where(User.id == user_id))
    user = result.scalar_one_or_none()
    if user is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User not found",
        )

    if not user.face_encoding:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="User has no face data registered",
        )

    user.face_encoding = None

    # Audit log
    audit = AuditLog(
        user_id=current_user.id,
        action="admin.reset_face_data",
        target_type="user",
        target_id=str(user_id),
        ip_address=request.client.host if request.client else None,
        details={"target_email": user.email},
    )
    db.add(audit)
    await db.flush()

    return {"message": f"Face data reset for user {user.email}"}
