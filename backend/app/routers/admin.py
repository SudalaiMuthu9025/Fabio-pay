"""
Fabio Backend — Admin Router
===============================
GET   /admin/users              — list all users (admin only)
PATCH /admin/users/{id}/role    — change user role
PATCH /admin/users/{id}/status  — activate/deactivate user
"""

from __future__ import annotations

import uuid

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select, func
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth import get_current_user, require_role
from app.database import get_db
from app.models import User, UserRole
from app.schemas import AdminUserOut, RoleUpdate, StatusUpdate

router = APIRouter(prefix="/admin", tags=["Admin"])


def _user_to_admin_out(user: User) -> AdminUserOut:
    """Convert ORM User to AdminUserOut with computed fields."""
    return AdminUserOut(
        id=user.id,
        email=user.email,
        full_name=user.full_name,
        phone=user.phone,
        role=user.role.value,
        is_active=user.is_active,
        is_face_registered=user.face_embedding is not None,
        has_pin=user.pin_hash is not None,
        has_bank_account=len(user.bank_accounts) > 0 if user.bank_accounts else False,
        created_at=user.created_at,
    )


# ── List All Users ───────────────────────────────────────────────────────────
@router.get(
    "/users",
    response_model=list[AdminUserOut],
    summary="List all users (admin only)",
    dependencies=[Depends(require_role(UserRole.ADMIN))],
)
async def list_users(
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(User).order_by(User.created_at.desc())
    )
    users = result.scalars().all()
    return [_user_to_admin_out(u) for u in users]


# ── Change Role ──────────────────────────────────────────────────────────────
@router.patch(
    "/users/{user_id}/role",
    response_model=AdminUserOut,
    summary="Change user role (admin only)",
    dependencies=[Depends(require_role(UserRole.ADMIN))],
)
async def change_role(
    user_id: uuid.UUID,
    body: RoleUpdate,
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(select(User).where(User.id == user_id))
    user = result.scalar_one_or_none()
    if user is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User not found",
        )
    user.role = UserRole(body.role)
    await db.flush()
    return _user_to_admin_out(user)


# ── Toggle Active Status ────────────────────────────────────────────────────
@router.patch(
    "/users/{user_id}/status",
    response_model=AdminUserOut,
    summary="Activate/deactivate user (admin only)",
    dependencies=[Depends(require_role(UserRole.ADMIN))],
)
async def toggle_status(
    user_id: uuid.UUID,
    body: StatusUpdate,
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(select(User).where(User.id == user_id))
    user = result.scalar_one_or_none()
    if user is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User not found",
        )
    user.is_active = body.is_active
    await db.flush()
    return _user_to_admin_out(user)
