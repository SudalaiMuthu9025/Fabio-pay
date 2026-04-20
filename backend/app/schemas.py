"""
Fabio Backend — Pydantic Schemas (Request / Response Models)
=============================================================
Grouped by domain: Auth, User, Face, Bank, Transaction.
"""

from __future__ import annotations

import uuid
from datetime import datetime
from decimal import Decimal
from typing import Optional

from pydantic import BaseModel, EmailStr, Field, ConfigDict


# ═══════════════════════════════════════════════════════════════════════════════
#  AUTH
# ═══════════════════════════════════════════════════════════════════════════════

class UserRegister(BaseModel):
    """POST /auth/register"""
    email: EmailStr
    full_name: str = Field(..., min_length=2, max_length=255)
    phone: Optional[str] = Field(None, max_length=20)
    password: str = Field(..., min_length=8, max_length=128)


class UserLogin(BaseModel):
    """POST /auth/login"""
    email: EmailStr
    password: str


class TokenResponse(BaseModel):
    """JWT token response."""
    access_token: str
    token_type: str = "bearer"


class SetPinRequest(BaseModel):
    """POST /auth/set-pin"""
    pin: str = Field(..., min_length=4, max_length=4, pattern=r"^\d{4}$")


# ═══════════════════════════════════════════════════════════════════════════════
#  USER
# ═══════════════════════════════════════════════════════════════════════════════

class UserOut(BaseModel):
    """Public user representation."""
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    email: str
    full_name: str
    phone: Optional[str] = None
    role: str
    is_active: bool
    is_face_registered: bool = False
    has_pin: bool = False
    has_bank_account: bool = False
    created_at: datetime


# ═══════════════════════════════════════════════════════════════════════════════
#  FACE
# ═══════════════════════════════════════════════════════════════════════════════

class FaceRegisterRequest(BaseModel):
    """POST /face/register — base64-encoded face image."""
    image: str = Field(..., description="Base64-encoded face image")


class FaceRegisterResponse(BaseModel):
    """Face registration response."""
    success: bool
    message: str


class FaceVerifyRequest(BaseModel):
    """POST /face/verify — base64-encoded live face image."""
    image: str = Field(..., description="Base64-encoded live face image")


class FaceVerifyResponse(BaseModel):
    """Face verification response."""
    verified: bool
    message: str


# ═══════════════════════════════════════════════════════════════════════════════
#  BANK ACCOUNT
# ═══════════════════════════════════════════════════════════════════════════════

class BankRegisterRequest(BaseModel):
    """POST /bank/register"""
    account_number: str = Field(..., min_length=8, max_length=34)
    ifsc_code: str = Field(..., max_length=11, pattern=r"^[A-Z]{4}0[A-Z0-9]{6}$")
    account_holder_name: str = Field(..., min_length=2, max_length=255)


class BankAccountOut(BaseModel):
    """Bank account response."""
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    user_id: uuid.UUID
    account_number: str
    ifsc_code: str
    account_holder_name: str
    balance: Decimal
    currency: str
    is_primary: bool
    created_at: datetime


# ═══════════════════════════════════════════════════════════════════════════════
#  TRANSACTIONS
# ═══════════════════════════════════════════════════════════════════════════════

class SendMoneyRequest(BaseModel):
    """POST /transactions/send"""
    to_account_identifier: str = Field(..., min_length=8, max_length=34)
    amount: Decimal = Field(..., gt=0)
    description: Optional[str] = None
    pin: str = Field(..., min_length=4, max_length=4, pattern=r"^\d{4}$")
    face_verified: bool = Field(
        default=False,
        description="Set to true after liveness + face verification passes"
    )


class TransactionOut(BaseModel):
    """Transaction response."""
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    user_id: uuid.UUID
    from_account_id: Optional[uuid.UUID] = None
    to_account_identifier: str
    amount: Decimal
    currency: str
    description: Optional[str] = None
    auth_method: str
    status: str
    created_at: datetime


class SendMoneyResponse(BaseModel):
    """Send money result."""
    transaction_id: uuid.UUID
    status: str
    auth_method: str
    message: str
    requires_liveness: bool = False
