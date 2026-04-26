"""
Fabio Backend — Payment Requests Router
=========================================
POST /requests/create        — create payment request
GET  /requests/incoming      — list requests awaiting your payment
GET  /requests/outgoing      — list requests you've sent
POST /requests/{id}/pay      — pay a pending request
POST /requests/{id}/decline  — decline a request
"""

from __future__ import annotations

from decimal import Decimal

from fastapi import APIRouter, Depends, HTTPException, Request, status
from sqlalchemy import select, or_
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth import get_current_user, verify_pin
from app.database import get_db
from app.models import (
    AuthMethod,
    BankAccount,
    PaymentRequest,
    PaymentRequestStatus,
    PaymentMode,
    Transaction,
    TransactionStatus,
    TransactionType,
    User,
)
from app.schemas import (
    PaymentRequestAction,
    PaymentRequestCreate,
    PaymentRequestOut,
)

router = APIRouter(prefix="/requests", tags=["Payment Requests"])


def _request_to_out(req: PaymentRequest, requester_name: str | None = None) -> PaymentRequestOut:
    return PaymentRequestOut(
        id=req.id,
        requester_id=req.requester_id,
        payer_account_identifier=req.payer_account_identifier,
        amount=req.amount,
        description=req.description,
        status=req.status.value,
        requester_name=requester_name,
        created_at=req.created_at,
    )


# ── Create Request ───────────────────────────────────────────────────────────
@router.post(
    "/create",
    response_model=PaymentRequestOut,
    status_code=status.HTTP_201_CREATED,
    summary="Send a payment request to another user",
)
async def create_request(
    body: PaymentRequestCreate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    # Validate the target account exists
    result = await db.execute(
        select(BankAccount).where(
            BankAccount.account_number == body.to_account_identifier
        )
    )
    target_acc = result.scalar_one_or_none()
    if target_acc is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Target account not found",
        )

    # Prevent self-request
    if target_acc.user_id == current_user.id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Cannot request money from yourself",
        )

    req = PaymentRequest(
        requester_id=current_user.id,
        payer_account_identifier=body.to_account_identifier,
        amount=body.amount,
        description=body.description,
    )
    db.add(req)
    await db.flush()
    await db.refresh(req)

    return _request_to_out(req, requester_name=current_user.full_name)


# ── Incoming Requests ────────────────────────────────────────────────────────
@router.get(
    "/incoming",
    response_model=list[PaymentRequestOut],
    summary="List payment requests awaiting your payment",
)
async def incoming_requests(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    # Find user's account numbers
    acc_result = await db.execute(
        select(BankAccount.account_number).where(
            BankAccount.user_id == current_user.id
        )
    )
    my_accounts = [row[0] for row in acc_result.all()]

    if not my_accounts:
        return []

    result = await db.execute(
        select(PaymentRequest)
        .where(
            PaymentRequest.payer_account_identifier.in_(my_accounts),
            PaymentRequest.status == PaymentRequestStatus.PENDING,
        )
        .order_by(PaymentRequest.created_at.desc())
    )
    requests = result.scalars().all()

    # Enrich with requester names
    out = []
    for req in requests:
        user_result = await db.execute(
            select(User.full_name).where(User.id == req.requester_id)
        )
        name = user_result.scalar_one_or_none()
        out.append(_request_to_out(req, requester_name=name))

    return out


# ── Outgoing Requests ────────────────────────────────────────────────────────
@router.get(
    "/outgoing",
    response_model=list[PaymentRequestOut],
    summary="List payment requests you've sent",
)
async def outgoing_requests(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(PaymentRequest)
        .where(PaymentRequest.requester_id == current_user.id)
        .order_by(PaymentRequest.created_at.desc())
    )
    return [_request_to_out(r, requester_name=current_user.full_name)
            for r in result.scalars().all()]


# ── Pay Request ──────────────────────────────────────────────────────────────
@router.post(
    "/{request_id}/pay",
    summary="Pay a pending payment request",
)
async def pay_request(
    request_id: str,
    body: PaymentRequestAction,
    request: Request,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    import uuid as _uuid
    try:
        req_uuid = _uuid.UUID(request_id)
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid request ID")

    result = await db.execute(
        select(PaymentRequest).where(PaymentRequest.id == req_uuid)
    )
    req = result.scalar_one_or_none()
    if req is None:
        raise HTTPException(status_code=404, detail="Request not found")

    if req.status != PaymentRequestStatus.PENDING:
        raise HTTPException(status_code=400, detail="Request already processed")

    # Verify this request is for the current user
    acc_result = await db.execute(
        select(BankAccount).where(
            BankAccount.user_id == current_user.id,
            BankAccount.account_number == req.payer_account_identifier,
        )
    )
    payer_account = acc_result.scalar_one_or_none()
    if payer_account is None:
        raise HTTPException(status_code=403, detail="This request is not for you")

    # Verify PIN
    if current_user.pin_hash is None:
        raise HTTPException(status_code=400, detail="PIN not set")
    if not verify_pin(body.pin, current_user.pin_hash):
        raise HTTPException(status_code=401, detail="Invalid PIN")

    # Check balance
    if payer_account.balance < req.amount:
        raise HTTPException(status_code=400, detail="Insufficient balance")

    # Get requester's primary account
    req_acc_result = await db.execute(
        select(BankAccount).where(
            BankAccount.user_id == req.requester_id,
            BankAccount.is_primary == True,
        )
    )
    requester_account = req_acc_result.scalar_one_or_none()

    # Execute transfer
    payer_account.balance -= req.amount
    if requester_account:
        requester_account.balance += req.amount

    client_ip = request.client.host if request.client else None

    # Create DEBIT for payer
    txn_debit = Transaction(
        user_id=current_user.id,
        counterpart_user_id=req.requester_id,
        transaction_type=TransactionType.DEBIT,
        from_account_id=payer_account.id,
        to_account_identifier=requester_account.account_number if requester_account else str(req.requester_id),
        amount=req.amount,
        currency="INR",
        description=req.description or "Payment request fulfilled",
        payment_mode=PaymentMode.ACCOUNT,
        auth_method=AuthMethod.PIN,
        status=TransactionStatus.SUCCESS,
        ip_address=client_ip,
    )
    db.add(txn_debit)

    # Create CREDIT for requester
    if requester_account:
        txn_credit = Transaction(
            user_id=req.requester_id,
            counterpart_user_id=current_user.id,
            transaction_type=TransactionType.CREDIT,
            from_account_id=payer_account.id,
            to_account_identifier=payer_account.account_number,
            amount=req.amount,
            currency="INR",
            description=req.description or f"Payment received from {current_user.full_name}",
            payment_mode=PaymentMode.ACCOUNT,
            auth_method=AuthMethod.PIN,
            status=TransactionStatus.SUCCESS,
            ip_address=client_ip,
        )
        db.add(txn_credit)

    req.status = PaymentRequestStatus.PAID
    await db.flush()

    return {"success": True, "message": f"₹{req.amount} paid successfully"}


# ── Decline Request ──────────────────────────────────────────────────────────
@router.post(
    "/{request_id}/decline",
    summary="Decline a payment request",
)
async def decline_request(
    request_id: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    import uuid as _uuid
    try:
        req_uuid = _uuid.UUID(request_id)
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid request ID")

    result = await db.execute(
        select(PaymentRequest).where(PaymentRequest.id == req_uuid)
    )
    req = result.scalar_one_or_none()
    if req is None:
        raise HTTPException(status_code=404, detail="Request not found")

    if req.status != PaymentRequestStatus.PENDING:
        raise HTTPException(status_code=400, detail="Request already processed")

    req.status = PaymentRequestStatus.DECLINED
    await db.flush()

    return {"success": True, "message": "Request declined"}
