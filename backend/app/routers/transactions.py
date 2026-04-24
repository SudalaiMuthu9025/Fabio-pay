"""
Fabio Backend — Transactions Router
=====================================
POST /transactions/send       — send money (creates DEBIT + CREDIT records)
POST /transactions/deposit    — add money to own account
GET  /transactions/history    — user's transaction history (sent + received)
"""

from __future__ import annotations

from decimal import Decimal

from fastapi import APIRouter, Depends, HTTPException, Request, status
from sqlalchemy import select, or_
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth import get_current_user, verify_pin
from app.config import settings
from app.database import get_db
from app.models import (
    AuthMethod,
    BankAccount,
    PaymentMode,
    Transaction,
    TransactionStatus,
    TransactionType,
    User,
)
from app.schemas import (
    DepositRequest,
    DepositResponse,
    SendMoneyRequest,
    SendMoneyResponse,
    TransactionOut,
)

router = APIRouter(prefix="/transactions", tags=["Transactions"])


# ── Send Money ────────────────────────────────────────────────────────────────
@router.post(
    "/send",
    response_model=SendMoneyResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Send money via Account Number, UPI ID, or QR",
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

    # 3. Validate payment mode specific inputs
    payment_mode = PaymentMode(body.payment_mode)

    if payment_mode == PaymentMode.UPI:
        if "@" not in body.to_account_identifier:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Invalid UPI ID. Must be in format: name@bank",
            )
    elif payment_mode == PaymentMode.ACCOUNT:
        if len(body.to_account_identifier) < 8:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Invalid account number. Must be at least 8 digits.",
            )

    # 4. Get sender's primary bank account
    result = await db.execute(
        select(BankAccount).where(
            BankAccount.user_id == current_user.id,
            BankAccount.is_primary == True,
        )
    )
    sender_account = result.scalar_one_or_none()
    if sender_account is None:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="No bank account found. Please register a bank account first.",
        )

    # 5. Validate recipient exists in database (for ACCOUNT mode)
    recipient_account = None
    recipient_user_id = None
    if payment_mode == PaymentMode.ACCOUNT:
        result = await db.execute(
            select(BankAccount).where(
                BankAccount.account_number == body.to_account_identifier
            )
        )
        recipient_account = result.scalar_one_or_none()
        if recipient_account is None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Recipient account number not found. Please verify the account number.",
            )
        # Prevent self-transfer
        if recipient_account.id == sender_account.id:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Cannot transfer to your own account.",
            )
        recipient_user_id = recipient_account.user_id

    # 6. Check sufficient balance
    if sender_account.balance < body.amount:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Insufficient balance. Available: ₹{sender_account.balance}",
        )

    # 7. Determine if liveness/face verification is required
    threshold = Decimal(str(settings.TRANSACTION_THRESHOLD))
    requires_liveness = body.amount >= threshold

    if requires_liveness and not body.face_verified:
        return SendMoneyResponse(
            transaction_id="00000000-0000-0000-0000-000000000000",
            status="pending",
            auth_method="biometric",
            message="Transaction amount exceeds threshold. Liveness verification required.",
            requires_liveness=True,
        )

    # 8. Execute double-entry: debit sender, credit receiver
    sender_account.balance -= body.amount

    if recipient_account is not None:
        recipient_account.balance += body.amount

    client_ip = request.client.host if request.client else None
    auth_method = AuthMethod.BIOMETRIC if requires_liveness else AuthMethod.PIN

    # 9. Create DEBIT record for sender
    txn_debit = Transaction(
        user_id=current_user.id,
        counterpart_user_id=recipient_user_id,
        transaction_type=TransactionType.DEBIT,
        from_account_id=sender_account.id,
        to_account_identifier=body.to_account_identifier,
        amount=body.amount,
        currency="INR",
        description=body.description,
        payment_mode=payment_mode,
        auth_method=auth_method,
        status=TransactionStatus.SUCCESS,
        ip_address=client_ip,
    )
    db.add(txn_debit)

    # 10. Create CREDIT record for receiver (if internal transfer)
    if recipient_account is not None and recipient_user_id is not None:
        txn_credit = Transaction(
            user_id=recipient_user_id,
            counterpart_user_id=current_user.id,
            transaction_type=TransactionType.CREDIT,
            from_account_id=sender_account.id,
            to_account_identifier=sender_account.account_number,
            amount=body.amount,
            currency="INR",
            description=body.description or f"Received from {current_user.full_name}",
            payment_mode=payment_mode,
            auth_method=auth_method,
            status=TransactionStatus.SUCCESS,
            ip_address=client_ip,
        )
        db.add(txn_credit)

    await db.flush()

    mode_label = {
        PaymentMode.UPI: "UPI",
        PaymentMode.ACCOUNT: "Bank Transfer",
        PaymentMode.QR: "QR Payment",
    }

    return SendMoneyResponse(
        transaction_id=txn_debit.id,
        status=txn_debit.status.value,
        auth_method=txn_debit.auth_method.value,
        message=f"{mode_label[payment_mode]} of ₹{body.amount} completed successfully",
        requires_liveness=False,
    )


# ── Deposit (Add Money) ─────────────────────────────────────────────────────
@router.post(
    "/deposit",
    response_model=DepositResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Add money to your own account",
)
async def deposit_money(
    body: DepositRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    # Verify PIN
    if current_user.pin_hash is None:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Transaction PIN not set.",
        )
    if not verify_pin(body.pin, current_user.pin_hash):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid PIN",
        )

    # Get primary account
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
            detail="No bank account found.",
        )

    # Credit account
    account.balance += body.amount
    await db.flush()

    return DepositResponse(
        success=True,
        new_balance=account.balance,
        message=f"₹{body.amount} added to your account successfully",
    )


# ── Transaction History ──────────────────────────────────────────────────────
@router.get(
    "/history",
    response_model=list[TransactionOut],
    summary="Get your transaction history (sent + received)",
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
