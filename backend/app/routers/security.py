"""
Fabio Backend — Security Settings Router
==========================================
GET   /api/security/   — view own security settings
PATCH /api/security/   — update threshold, PIN, biometric toggle
"""

from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth import get_current_user, hash_pin
from app.database import get_db
from app.models import User
from app.schemas import SecuritySettingsOut, SecuritySettingsUpdate

router = APIRouter(prefix="/api/security", tags=["Security Settings"])


# ── Get Settings ──────────────────────────────────────────────────────────────
@router.get("/", response_model=SecuritySettingsOut, summary="View security settings")
async def get_security_settings(
    current_user: User = Depends(get_current_user),
):
    if current_user.security_settings is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Security settings not found",
        )
    return current_user.security_settings


# ── Update Settings ──────────────────────────────────────────────────────────
@router.patch("/", response_model=SecuritySettingsOut, summary="Update security settings")
async def update_security_settings(
    body: SecuritySettingsUpdate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    sec = current_user.security_settings
    if sec is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Security settings not found",
        )

    update_data = body.model_dump(exclude_unset=True)
    if not update_data:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="No fields to update",
        )

    # Hash PIN if being updated
    if "pin" in update_data:
        sec.pin_hash = hash_pin(update_data.pop("pin"))

    for field, value in update_data.items():
        setattr(sec, field, value)

    await db.flush()
    return sec
