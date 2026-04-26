"""
Fabio Backend — QR Code Router
================================
GET  /qr/my-code  — get QR payload for current user's account
POST /qr/decode   — validate a QR payload and return account info
"""

from __future__ import annotations

import json

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth import get_current_user
from app.database import get_db
from app.models import BankAccount, User


router = APIRouter(prefix="/qr", tags=["QR"])


class QrPayload(BaseModel):
    """QR code payload schema."""
    account_number: str
    name: str
    ifsc: str


class QrDecodeRequest(BaseModel):
    """POST /qr/decode"""
    payload: str


class QrDecodeResponse(BaseModel):
    """Decoded QR response."""
    account_number: str
    name: str
    ifsc: str
    valid: bool = True


@router.get(
    "/my-code",
    response_model=QrPayload,
    summary="Get QR payload for your primary account",
)
async def my_qr_code(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
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
            detail="No bank account found. Register a bank account first.",
        )

    return QrPayload(
        account_number=account.account_number,
        name=account.account_holder_name,
        ifsc=account.ifsc_code,
    )


@router.post(
    "/decode",
    response_model=QrDecodeResponse,
    summary="Decode and validate a QR payment payload",
)
async def decode_qr(
    body: QrDecodeRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    try:
        data = json.loads(body.payload)
    except (json.JSONDecodeError, TypeError):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid QR code payload",
        )

    account_number = data.get("account_number", "")
    if not account_number:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="QR code missing account number",
        )

    # Validate account exists
    result = await db.execute(
        select(BankAccount).where(
            BankAccount.account_number == account_number
        )
    )
    account = result.scalar_one_or_none()
    if account is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Account not found for this QR code",
        )

    return QrDecodeResponse(
        account_number=account.account_number,
        name=account.account_holder_name,
        ifsc=account.ifsc_code,
        valid=True,
    )
