"""
Fabio Backend — Transactions Router
=====================================
POST /transactions/send     — send money (PIN + optional face verification)
GET  /transactions/history  — user's transaction history
"""

from __future__ import annotations

from decimal import Decimal

from fastapi import APIRouter, Depends, HTTPException, Request, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth import get_current_user, verify_pin
from app.config import settings
from app.database import get_db
from app.models import (
    AuthMethod,
    BankAccount,
    Transaction,
    TransactionStatus,
    User,
)
from app.schemas import SendMoneyRequest, SendMoneyResponse, TransactionOut

router = APIRouter(prefix="/transactions", tags=["Transactions"])


# ── Send Money ────────────────────────────────────────────────────────────────
@router.post(
    "/send",
    response_model=SendMoneyResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Send money to another account",
)
async def send_money(
    body: SendMoneyRequest,
    request: Request,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    # 1. Check PIN is set
    if current_user.pin_hash is None:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Transaction PIN not set. Please set your PIN first.",
        )

    # 2. Verify PIN
    if not verify_pin(body.pin, current_user.pin_hash):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid PIN",
        )

    # 3. Get user's primary bank account
    result = await db.execute(
        select(BankAccount).where(
            BankAccount.user_id == current_user.id,
            BankAccount.is_primary == True,
        )
    )
    account = result.scalar_one_or_none()
    if account is None:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="No bank account found. Please register a bank account first.",
        )

    # 4. Check sufficient balance
    if account.balance < body.amount:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Insufficient balance",
        )

    # 5. Determine if liveness/face verification is required
    threshold = Decimal(str(settings.TRANSACTION_THRESHOLD))
    requires_liveness = body.amount >= threshold

    if requires_liveness and not body.face_verified:
        # Don't execute — tell the client to perform liveness check first
        return SendMoneyResponse(
            transaction_id="00000000-0000-0000-0000-000000000000",
            status="pending",
            auth_method="biometric",
            message="Transaction amount exceeds threshold. Liveness verification required.",
            requires_liveness=True,
        )

    # 6. Debit and create transaction
    account.balance -= body.amount
    client_ip = request.client.host if request.client else None

    auth_method = AuthMethod.BIOMETRIC if requires_liveness else AuthMethod.PIN

    txn = Transaction(
        user_id=current_user.id,
        from_account_id=account.id,
        to_account_identifier=body.to_account_identifier,
        amount=body.amount,
        currency="INR",
        description=body.description,
        auth_method=auth_method,
        status=TransactionStatus.SUCCESS,
        ip_address=client_ip,
    )
    db.add(txn)
    await db.flush()

    return SendMoneyResponse(
        transaction_id=txn.id,
        status=txn.status.value,
        auth_method=txn.auth_method.value,
        message="Transfer completed successfully",
        requires_liveness=False,
    )


# ── Transaction History ──────────────────────────────────────────────────────
@router.get(
    "/history",
    response_model=list[TransactionOut],
    summary="Get your transaction history",
)
async def transaction_history(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(Transaction)
        .where(Transaction.user_id == current_user.id)
        .order_by(Transaction.created_at.desc())
    )
    return result.scalars().all()
