"""
Fabio Backend — Users Router
==============================
GET   /api/users/me   — own profile (User)
PATCH /api/users/me   — update own profile (User)
GET   /api/users/     — list all users (Admin only)
"""

from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth import get_current_user, require_role
from app.database import get_db
from app.models import User, UserRole
from app.schemas import UserOut, UserUpdate

router = APIRouter(prefix="/api/users", tags=["Users"])


# ── Get Own Profile ───────────────────────────────────────────────────────────
@router.get("/me", response_model=UserOut, summary="Get your profile")
async def get_me(current_user: User = Depends(get_current_user)):
    return current_user


# ── Update Own Profile ────────────────────────────────────────────────────────
@router.patch("/me", response_model=UserOut, summary="Update your profile")
async def update_me(
    body: UserUpdate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    update_data = body.model_dump(exclude_unset=True)
    if not update_data:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="No fields to update",
        )

    # Check email uniqueness if changing email
    if "email" in update_data:
        existing = await db.execute(
            select(User).where(
                User.email == update_data["email"], User.id != current_user.id
            )
        )
        if existing.scalar_one_or_none():
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="Email already in use",
            )

    for field, value in update_data.items():
        setattr(current_user, field, value)

    await db.flush()
    return current_user


# ── List All Users (Admin) ───────────────────────────────────────────────────
@router.get(
    "/",
    response_model=list[UserOut],
    summary="List all users (Admin only)",
    dependencies=[Depends(require_role(UserRole.ADMIN))],
)
async def list_users(db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(User).order_by(User.created_at.desc()))
    return result.scalars().all()
