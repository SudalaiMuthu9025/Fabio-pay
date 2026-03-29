"""
Fabio Backend — Bank Accounts Router
======================================
POST   /api/accounts/       — add bank account
GET    /api/accounts/       — list own accounts
GET    /api/accounts/{id}   — get single account
PATCH  /api/accounts/{id}   — update account
DELETE /api/accounts/{id}   — remove account
"""

from __future__ import annotations

import uuid

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth import get_current_user
from app.database import get_db
from app.models import BankAccount, User
from app.schemas import AccountCreate, AccountOut, AccountUpdate

router = APIRouter(prefix="/api/accounts", tags=["Bank Accounts"])


# ── Helpers ───────────────────────────────────────────────────────────────────

async def _get_user_account(
    account_id: uuid.UUID,
    user: User,
    db: AsyncSession,
) -> BankAccount:
    """Fetch an account that belongs to the current user, or 404."""
    result = await db.execute(
        select(BankAccount).where(
            BankAccount.id == account_id,
            BankAccount.user_id == user.id,
        )
    )
    account = result.scalar_one_or_none()
    if account is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Account not found",
        )
    return account


# ── Create ────────────────────────────────────────────────────────────────────
@router.post(
    "/",
    response_model=AccountOut,
    status_code=status.HTTP_201_CREATED,
    summary="Add a bank account",
)
async def create_account(
    body: AccountCreate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    # Check duplicate account number
    exists = await db.execute(
        select(BankAccount).where(
            BankAccount.account_number == body.account_number
        )
    )
    if exists.scalar_one_or_none():
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Account number already registered",
        )

    account = BankAccount(
        user_id=current_user.id,
        **body.model_dump(),
    )
    db.add(account)
    await db.flush()
    return account


# ── List Own ──────────────────────────────────────────────────────────────────
@router.get("/", response_model=list[AccountOut], summary="List your accounts")
async def list_accounts(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(BankAccount)
        .where(BankAccount.user_id == current_user.id)
        .order_by(BankAccount.created_at.desc())
    )
    return result.scalars().all()


# ── Get One ───────────────────────────────────────────────────────────────────
@router.get("/{account_id}", response_model=AccountOut, summary="Get account detail")
async def get_account(
    account_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    return await _get_user_account(account_id, current_user, db)


# ── Update ────────────────────────────────────────────────────────────────────
@router.patch("/{account_id}", response_model=AccountOut, summary="Update account")
async def update_account(
    account_id: uuid.UUID,
    body: AccountUpdate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    account = await _get_user_account(account_id, current_user, db)
    update_data = body.model_dump(exclude_unset=True)

    if not update_data:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="No fields to update",
        )

    for field, value in update_data.items():
        setattr(account, field, value)

    await db.flush()
    return account


# ── Delete ────────────────────────────────────────────────────────────────────
@router.delete(
    "/{account_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Remove account",
)
async def delete_account(
    account_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    account = await _get_user_account(account_id, current_user, db)
    await db.delete(account)
    await db.flush()
