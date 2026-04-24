"""
Fabio Backend — Profile Router
================================
PATCH /profile/update           — update name, phone
POST  /profile/change-password  — change password
GET   /profile/login-history    — view login history
POST  /profile/re-register-face — re-register face (replaces old embedding)
"""

from __future__ import annotations

import base64

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth import get_current_user, hash_password, hash_pin, verify_password, verify_pin
from app.database import get_db
from app.face_utils import extract_face_embedding
from app.models import FaceEmbedding, LoginLog, User
from app.schemas import (
    ChangePassword,
    ChangePinRequest,
    FaceRegisterRequest,
    FaceRegisterResponse,
    LoginLogOut,
    ProfileUpdate,
    UserOut,
)
from app.routers.auth import _user_to_out

router = APIRouter(prefix="/profile", tags=["Profile"])


# ── Update Profile ───────────────────────────────────────────────────────────
@router.patch(
    "/update",
    response_model=UserOut,
    summary="Update profile (name, phone)",
)
async def update_profile(
    body: ProfileUpdate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    update_data = body.model_dump(exclude_unset=True)
    if not update_data:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="No fields to update",
        )
    for field, value in update_data.items():
        setattr(current_user, field, value)
    await db.flush()
    return _user_to_out(current_user)


# ── Change Password ─────────────────────────────────────────────────────────
@router.post(
    "/change-password",
    summary="Change password",
)
async def change_password(
    body: ChangePassword,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    if not verify_password(body.current_password, current_user.hashed_password):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Current password is incorrect",
        )
    current_user.hashed_password = hash_password(body.new_password)
    await db.flush()
    return {"success": True, "message": "Password changed successfully"}


# ── Change PIN ─────────────────────────────────────────────────────────────────
@router.post(
    "/change-pin",
    summary="Change transaction PIN",
)
async def change_pin(
    body: ChangePinRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    if current_user.pin_hash is None:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="PIN not set. Use /auth/set-pin first.",
        )
    if not verify_pin(body.current_pin, current_user.pin_hash):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Current PIN is incorrect",
        )
    if body.current_pin == body.new_pin:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="New PIN must be different from current PIN",
        )
    current_user.pin_hash = hash_pin(body.new_pin)
    await db.flush()
    return {"success": True, "message": "PIN changed successfully"}


# ── Login History ────────────────────────────────────────────────────────────
@router.get(
    "/login-history",
    response_model=list[LoginLogOut],
    summary="View login history",
)
async def login_history(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(LoginLog)
        .where(LoginLog.user_id == current_user.id)
        .order_by(LoginLog.created_at.desc())
        .limit(20)
    )
    return result.scalars().all()


# ── Re-register Face ────────────────────────────────────────────────────────
@router.post(
    "/re-register-face",
    response_model=FaceRegisterResponse,
    summary="Re-register face (replaces old embedding)",
)
async def re_register_face(
    body: FaceRegisterRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    embedding = extract_face_embedding(body.image)
    if embedding is None:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="No face detected. Please try again with a clear photo.",
        )

    if current_user.face_embedding is not None:
        # Update existing
        current_user.face_embedding.embedding = embedding
    else:
        # Create new
        face = FaceEmbedding(
            user_id=current_user.id,
            embedding=embedding,
        )
        db.add(face)

    await db.flush()
    return FaceRegisterResponse(
        success=True,
        message="Face re-registered successfully",
    )
