"""
Fabio Backend — Beneficiary Router
=====================================
POST   /beneficiary/add              — save a new recipient
GET    /beneficiary/list             — list saved recipients
DELETE /beneficiary/{id}             — remove a saved recipient
PATCH  /beneficiary/{id}/favorite    — toggle favorite
"""

from __future__ import annotations

import uuid

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth import get_current_user
from app.database import get_db
from app.models import Beneficiary, User
from app.schemas import BeneficiaryCreate, BeneficiaryOut

router = APIRouter(prefix="/beneficiary", tags=["Beneficiary"])


# ── Add Beneficiary ──────────────────────────────────────────────────────────
@router.post(
    "/add",
    response_model=BeneficiaryOut,
    status_code=status.HTTP_201_CREATED,
    summary="Save a new recipient",
)
async def add_beneficiary(
    body: BeneficiaryCreate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    # Check for duplicate
    exists = await db.execute(
        select(Beneficiary).where(
            Beneficiary.user_id == current_user.id,
            Beneficiary.account_number == body.account_number,
        )
    )
    if exists.scalar_one_or_none():
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Beneficiary with this account already exists",
        )

    beneficiary = Beneficiary(
        user_id=current_user.id,
        name=body.name,
        account_number=body.account_number,
        ifsc_code=body.ifsc_code,
        nickname=body.nickname,
    )
    db.add(beneficiary)
    await db.flush()
    return beneficiary


# ── List Beneficiaries ───────────────────────────────────────────────────────
@router.get(
    "/list",
    response_model=list[BeneficiaryOut],
    summary="List saved recipients",
)
async def list_beneficiaries(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(Beneficiary)
        .where(Beneficiary.user_id == current_user.id)
        .order_by(Beneficiary.is_favorite.desc(), Beneficiary.created_at.desc())
    )
    return result.scalars().all()


# ── Delete Beneficiary ──────────────────────────────────────────────────────
@router.delete(
    "/{beneficiary_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Remove a saved recipient",
)
async def delete_beneficiary(
    beneficiary_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(Beneficiary).where(
            Beneficiary.id == beneficiary_id,
            Beneficiary.user_id == current_user.id,
        )
    )
    beneficiary = result.scalar_one_or_none()
    if beneficiary is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Beneficiary not found",
        )
    await db.delete(beneficiary)
    await db.flush()


# ── Toggle Favorite ──────────────────────────────────────────────────────────
@router.patch(
    "/{beneficiary_id}/favorite",
    response_model=BeneficiaryOut,
    summary="Toggle beneficiary favorite status",
)
async def toggle_favorite(
    beneficiary_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(Beneficiary).where(
            Beneficiary.id == beneficiary_id,
            Beneficiary.user_id == current_user.id,
        )
    )
    beneficiary = result.scalar_one_or_none()
    if beneficiary is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Beneficiary not found",
        )
    beneficiary.is_favorite = not beneficiary.is_favorite
    await db.flush()
    return beneficiary
