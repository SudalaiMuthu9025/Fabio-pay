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


class VerifyPinRequest(BaseModel):
    """POST /auth/verify-pin"""
    pin: str = Field(..., min_length=4, max_length=4, pattern=r"^\d{4}$")


class ChangePinRequest(BaseModel):
    """POST /profile/change-pin"""
    current_pin: str = Field(..., min_length=4, max_length=4, pattern=r"^\d{4}$")
    new_pin: str = Field(..., min_length=4, max_length=4, pattern=r"^\d{4}$")


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
    to_account_identifier: str = Field(..., min_length=3, max_length=255,
        description="Bank account number or UPI ID (e.g. user@upi)")
    amount: Decimal = Field(..., gt=0)
    description: Optional[str] = None
    pin: str = Field(..., min_length=4, max_length=4, pattern=r"^\d{4}$")
    payment_mode: str = Field(
        default="ACCOUNT",
        pattern=r"^(ACCOUNT|UPI|QR)$",
        description="Payment mode: ACCOUNT, UPI, or QR"
    )
    face_verified: bool = Field(
        default=False,
        description="Set to true after liveness + face verification passes"
    )


class TransactionOut(BaseModel):
    """Transaction response."""
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    user_id: uuid.UUID
    counterpart_user_id: Optional[uuid.UUID] = None
    transaction_type: str = "DEBIT"
    from_account_id: Optional[uuid.UUID] = None
    to_account_identifier: str
    amount: Decimal
    currency: str
    description: Optional[str] = None
    payment_mode: str = "ACCOUNT"
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


class DepositRequest(BaseModel):
    """POST /transactions/deposit"""
    amount: Decimal = Field(..., gt=0, le=100000,
        description="Amount to deposit (max ₹1,00,000)")
    pin: str = Field(..., min_length=4, max_length=4, pattern=r"^\d{4}$")


class DepositResponse(BaseModel):
    """Deposit result."""
    success: bool
    new_balance: Decimal
    message: str

# ═══════════════════════════════════════════════════════════════════════════════
#  BENEFICIARY
# ═══════════════════════════════════════════════════════════════════════════════

class BeneficiaryCreate(BaseModel):
    """POST /beneficiary/add"""
    name: str = Field(..., min_length=2, max_length=255)
    account_number: str = Field(..., min_length=8, max_length=34)
    ifsc_code: Optional[str] = Field(None, max_length=11)
    nickname: Optional[str] = Field(None, max_length=50)


class BeneficiaryOut(BaseModel):
    """Beneficiary response."""
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    user_id: uuid.UUID
    name: str
    account_number: str
    ifsc_code: Optional[str] = None
    nickname: Optional[str] = None
    is_favorite: bool
    created_at: datetime


# ═══════════════════════════════════════════════════════════════════════════════
#  PROFILE
# ═══════════════════════════════════════════════════════════════════════════════

class ProfileUpdate(BaseModel):
    """PATCH /profile/update"""
    full_name: Optional[str] = Field(None, min_length=2, max_length=255)
    phone: Optional[str] = Field(None, max_length=20)


class ChangePassword(BaseModel):
    """POST /profile/change-password"""
    current_password: str = Field(..., min_length=8)
    new_password: str = Field(..., min_length=8, max_length=128)


class LoginLogOut(BaseModel):
    """Login log entry."""
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    ip_address: Optional[str] = None
    user_agent: Optional[str] = None
    success: bool
    created_at: datetime


# ═══════════════════════════════════════════════════════════════════════════════
#  ADMIN
# ═══════════════════════════════════════════════════════════════════════════════

class AdminUserOut(BaseModel):
    """Admin view of a user."""
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


class RoleUpdate(BaseModel):
    """PATCH /admin/users/{id}/role"""
    role: str = Field(..., pattern=r"^(USER|ADMIN)$")


class StatusUpdate(BaseModel):
    """PATCH /admin/users/{id}/status"""
    is_active: bool


# ═══════════════════════════════════════════════════════════════════════════════
#  TRANSACTION DETAIL (for receipts)
# ═══════════════════════════════════════════════════════════════════════════════

class TransactionDetailOut(BaseModel):
    """GET /transactions/{id} — full receipt detail."""
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    user_id: uuid.UUID
    counterpart_user_id: Optional[uuid.UUID] = None
    transaction_type: str = "DEBIT"
    from_account_id: Optional[uuid.UUID] = None
    to_account_identifier: str
    amount: Decimal
    currency: str
    description: Optional[str] = None
    payment_mode: str = "ACCOUNT"
    auth_method: str
    status: str
    ip_address: Optional[str] = None
    created_at: datetime
    # Enriched fields for receipt
    sender_name: Optional[str] = None
    receiver_name: Optional[str] = None
    sender_account: Optional[str] = None
    receiver_account: Optional[str] = None


# ═══════════════════════════════════════════════════════════════════════════════
#  SPENDING ANALYTICS
# ═══════════════════════════════════════════════════════════════════════════════

class DailySpending(BaseModel):
    """Single day's spending summary."""
    date: str
    sent: Decimal = Decimal("0")
    received: Decimal = Decimal("0")


class MonthlySpending(BaseModel):
    """Single month's spending summary."""
    month: str
    sent: Decimal = Decimal("0")
    received: Decimal = Decimal("0")


class SpendingSummary(BaseModel):
    """GET /analytics/spending-summary response."""
    weekly: list[DailySpending] = []
    monthly: list[MonthlySpending] = []
    total_sent: Decimal = Decimal("0")
    total_received: Decimal = Decimal("0")


# ═══════════════════════════════════════════════════════════════════════════════
#  PAYMENT REQUESTS
# ═══════════════════════════════════════════════════════════════════════════════

class PaymentRequestCreate(BaseModel):
    """POST /requests/create"""
    to_account_identifier: str = Field(..., min_length=3, max_length=255)
    amount: Decimal = Field(..., gt=0)
    description: Optional[str] = None


class PaymentRequestOut(BaseModel):
    """Payment request response."""
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    requester_id: uuid.UUID
    payer_account_identifier: str
    amount: Decimal
    description: Optional[str] = None
    status: str
    requester_name: Optional[str] = None
    created_at: datetime


class PaymentRequestAction(BaseModel):
    """POST /requests/{id}/pay"""
    pin: str = Field(..., min_length=4, max_length=4, pattern=r"^\d{4}$")


# ═══════════════════════════════════════════════════════════════════════════════
#  TRANSACTION LIMITS
# ═══════════════════════════════════════════════════════════════════════════════

class UpdateLimitsRequest(BaseModel):
    """POST /profile/update-limits"""
    daily_transfer_limit: Optional[Decimal] = Field(None, gt=0, le=10000000)
    monthly_transfer_limit: Optional[Decimal] = Field(None, gt=0, le=100000000)


class LimitsResponse(BaseModel):
    """GET /profile/limits"""
    daily_transfer_limit: Decimal
    monthly_transfer_limit: Decimal
    daily_used: Decimal = Decimal("0")
    monthly_used: Decimal = Decimal("0")
    daily_remaining: Decimal = Decimal("0")
    monthly_remaining: Decimal = Decimal("0")

