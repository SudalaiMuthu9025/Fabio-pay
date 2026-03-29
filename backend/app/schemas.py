"""
Fabio Backend — Pydantic Schemas (Request / Response Models)
=============================================================
Grouped by domain: Auth, User, BankAccount, Security, Transaction.
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
    """POST /api/auth/register"""
    email: EmailStr
    full_name: str = Field(..., min_length=2, max_length=255)
    password: str = Field(..., min_length=8, max_length=128)
    pin: str = Field(..., min_length=4, max_length=6, pattern=r"^\d{4,6}$")


class UserLogin(BaseModel):
    """POST /api/auth/login"""
    email: EmailStr
    password: str


class Token(BaseModel):
    """JWT response payload."""
    access_token: str
    token_type: str = "bearer"


class TokenData(BaseModel):
    """Decoded JWT claims."""
    user_id: uuid.UUID
    role: str


# ═══════════════════════════════════════════════════════════════════════════════
#  USER
# ═══════════════════════════════════════════════════════════════════════════════

class UserOut(BaseModel):
    """Public user representation."""
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    email: str
    full_name: str
    role: str
    is_active: bool
    created_at: datetime


class UserUpdate(BaseModel):
    """PATCH /api/users/me"""
    full_name: Optional[str] = Field(None, min_length=2, max_length=255)
    email: Optional[EmailStr] = None


# ═══════════════════════════════════════════════════════════════════════════════
#  BANK ACCOUNT
# ═══════════════════════════════════════════════════════════════════════════════

class AccountCreate(BaseModel):
    """POST /api/accounts/"""
    account_number: str = Field(..., min_length=8, max_length=34)
    bank_name: str = Field(..., min_length=2, max_length=255)
    balance: Decimal = Field(default=Decimal("0.00"), ge=0)
    currency: str = Field(default="INR", max_length=3)
    is_primary: bool = False


class AccountUpdate(BaseModel):
    """PATCH /api/accounts/{id}"""
    bank_name: Optional[str] = Field(None, min_length=2, max_length=255)
    is_primary: Optional[bool] = None


class AccountOut(BaseModel):
    """Bank account response."""
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    user_id: uuid.UUID
    account_number: str
    bank_name: str
    balance: Decimal
    currency: str
    is_primary: bool
    created_at: datetime


# ═══════════════════════════════════════════════════════════════════════════════
#  SECURITY SETTINGS
# ═══════════════════════════════════════════════════════════════════════════════

class SecuritySettingsCreate(BaseModel):
    """Created automatically on registration."""
    pin: str = Field(..., min_length=4, max_length=6, pattern=r"^\d{4,6}$")
    threshold_amount: Decimal = Field(default=Decimal("10000.00"), ge=0)


class SecuritySettingsUpdate(BaseModel):
    """PATCH /api/security/"""
    threshold_amount: Optional[Decimal] = Field(None, ge=0)
    pin: Optional[str] = Field(None, min_length=4, max_length=6, pattern=r"^\d{4,6}$")
    biometric_enabled: Optional[bool] = None


class SecuritySettingsOut(BaseModel):
    """Security settings response (never exposes pin_hash)."""
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    user_id: uuid.UUID
    threshold_amount: Decimal
    biometric_enabled: bool
    max_attempts: int
    lockout_duration_minutes: int
    failed_attempts: int
    locked_until: Optional[datetime] = None
    created_at: datetime


# ═══════════════════════════════════════════════════════════════════════════════
#  TRANSACTIONS
# ═══════════════════════════════════════════════════════════════════════════════

class TransferRequest(BaseModel):
    """POST /api/transactions/transfer"""
    from_account_id: uuid.UUID
    to_account_identifier: str = Field(..., min_length=8, max_length=34)
    amount: Decimal = Field(..., gt=0)
    currency: str = Field(default="INR", max_length=3)
    description: Optional[str] = None
    pin: Optional[str] = Field(
        None, min_length=4, max_length=6, pattern=r"^\d{4,6}$",
        description="Required when amount < user threshold"
    )


class TransferOut(BaseModel):
    """Transfer initiation response."""
    model_config = ConfigDict(from_attributes=True)

    transaction_id: uuid.UUID
    status: str
    auth_method: str
    message: str
    challenge_sequence: Optional[list[str]] = None  # populated when biometric required


class TransactionLogOut(BaseModel):
    """Transaction history item."""
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    user_id: uuid.UUID
    from_account_id: Optional[uuid.UUID] = None
    to_account_identifier: Optional[str] = None
    amount: Decimal
    currency: str
    description: Optional[str] = None
    auth_method: str
    status: str
    risk_score: Optional[Decimal] = None
    challenge_sequence: Optional[dict] = None
    ip_address: Optional[str] = None
    created_at: datetime
