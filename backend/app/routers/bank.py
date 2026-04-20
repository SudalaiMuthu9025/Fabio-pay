"""
Fabio Backend — Bank Router
=============================
POST /bank/register  — register a bank account
GET  /bank/account   — get user's bank account(s)
"""

from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth import get_current_user
from app.database import get_db
from app.models import BankAccount, User
from app.schemas import BankAccountOut, BankRegisterRequest

router = APIRouter(prefix="/bank", tags=["Bank"])


# ── Register Bank Account ────────────────────────────────────────────────────
@router.post(
    "/register",
    response_model=BankAccountOut,
    status_code=status.HTTP_201_CREATED,
    summary="Register a bank account",
)
async def register_bank(
    body: BankRegisterRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    # Check if account number already exists
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
        account_number=body.account_number,
        ifsc_code=body.ifsc_code,
        account_holder_name=body.account_holder_name,
        is_primary=True,
    )
    db.add(account)
    await db.flush()

    return account


# ── Get Bank Account(s) ──────────────────────────────────────────────────────
@router.get(
    "/account",
    response_model=list[BankAccountOut],
    summary="Get user's bank accounts",
)
async def get_accounts(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(BankAccount).where(BankAccount.user_id == current_user.id)
    )
    return result.scalars().all()
