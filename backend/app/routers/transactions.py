"""
Fabio Backend — Transactions Router
=====================================
POST /api/transactions/transfer   — risk-based transfer initiation
GET  /api/transactions/           — own transaction history
GET  /api/transactions/logs       — system-wide logs (Admin)
"""

from __future__ import annotations

import random
import uuid

from fastapi import APIRouter, Depends, HTTPException, Request, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth import get_current_user, require_role, verify_pin
from app.database import get_db
from app.models import (
    AuthMethod,
    BankAccount,
    TransactionLog,
    TransactionStatus,
    User,
    UserRole,
)
from app.schemas import TransactionLogOut, TransferOut, TransferRequest

router = APIRouter(prefix="/api/transactions", tags=["Transactions"])

# ── Available biometric challenges ────────────────────────────────────────────
CHALLENGE_ACTIONS: list[str] = ["Blink", "Smile", "Smirk"]


def _generate_challenge(count: int = 3) -> list[str]:
    """Generate a random sequence of *count* challenge actions."""
    return random.sample(CHALLENGE_ACTIONS, k=min(count, len(CHALLENGE_ACTIONS)))


# ── Transfer ──────────────────────────────────────────────────────────────────
@router.post(
    "/transfer",
    response_model=TransferOut,
    status_code=status.HTTP_201_CREATED,
    summary="Initiate a risk-based transfer",
)
async def transfer(
    body: TransferRequest,
    request: Request,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    # 1. Verify the source account belongs to the user
    result = await db.execute(
        select(BankAccount).where(
            BankAccount.id == body.from_account_id,
            BankAccount.user_id == current_user.id,
        )
    )
    account = result.scalar_one_or_none()
    if account is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Source account not found",
        )

    # 2. Check sufficient balance
    if account.balance < body.amount:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Insufficient balance",
        )

    # 3. Load security settings
    sec = current_user.security_settings
    if sec is None:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Security settings not configured",
        )

    # 4. Risk-based auth routing
    client_ip = request.client.host if request.client else None

    if body.amount < sec.threshold_amount:
        # ── LOW RISK: PIN verification ────────────────────────────────────
        if not body.pin:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="PIN is required for this transaction amount",
            )
        if not verify_pin(body.pin, sec.pin_hash):
            # Track failed attempt
            sec.failed_attempts += 1
            await db.flush()
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid PIN",
            )

        # Debit & log
        account.balance -= body.amount

        txn = TransactionLog(
            user_id=current_user.id,
            from_account_id=account.id,
            to_account_identifier=body.to_account_identifier,
            amount=body.amount,
            currency=body.currency,
            description=body.description,
            auth_method=AuthMethod.PIN,
            status=TransactionStatus.SUCCESS,
            ip_address=client_ip,
        )
        db.add(txn)
        await db.flush()

        # Reset failed attempts on success
        sec.failed_attempts = 0
        await db.flush()

        return TransferOut(
            transaction_id=txn.id,
            status=txn.status.value,
            auth_method=txn.auth_method.value,
            message="Transfer completed successfully",
        )

    else:
        # ── HIGH RISK: Biometric challenge required ───────────────────────
        challenge = _generate_challenge()

        txn = TransactionLog(
            user_id=current_user.id,
            from_account_id=account.id,
            to_account_identifier=body.to_account_identifier,
            amount=body.amount,
            currency=body.currency,
            description=body.description,
            auth_method=AuthMethod.BIOMETRIC,
            status=TransactionStatus.PENDING,
            challenge_sequence={"sequence": challenge, "results": []},
            ip_address=client_ip,
        )
        db.add(txn)
        await db.flush()

        return TransferOut(
            transaction_id=txn.id,
            status=txn.status.value,
            auth_method=txn.auth_method.value,
            message="Biometric verification required — complete the challenge",
            challenge_sequence=challenge,
        )


# ── Own Transaction History ──────────────────────────────────────────────────
@router.get(
    "/",
    response_model=list[TransactionLogOut],
    summary="List your transactions",
)
async def list_own_transactions(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(TransactionLog)
        .where(TransactionLog.user_id == current_user.id)
        .order_by(TransactionLog.created_at.desc())
    )
    return result.scalars().all()


# ── System-Wide Logs (Admin) ─────────────────────────────────────────────────
@router.get(
    "/logs",
    response_model=list[TransactionLogOut],
    summary="System-wide transaction logs (Admin)",
    dependencies=[Depends(require_role(UserRole.ADMIN))],
)
async def admin_transaction_logs(db: AsyncSession = Depends(get_db)):
    result = await db.execute(
        select(TransactionLog).order_by(TransactionLog.created_at.desc()).limit(200)
    )
    return result.scalars().all()
