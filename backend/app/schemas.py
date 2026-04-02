"""
Fabio Backend — Pydantic Schemas (Request / Response Models)
=============================================================
Grouped by domain: Auth, User, BankAccount, Security, Transaction, Admin.
"""

from __future__ import annotations

import uuid
from datetime import datetime
from decimal import Decimal
from typing import Optional

from pydantic import BaseModel, EmailStr, Field, ConfigDict, model_validator


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


class SessionToken(BaseModel):
    """Session token response (replaces JWT Token)."""
    session_token: str
    token_type: str = "bearer"
    expires_in_hours: int = 24


class GoogleAuthRequest(BaseModel):
    """POST /api/auth/google"""
    id_token: str = Field(..., description="Google ID token from client-side sign-in")


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
    google_id: Optional[str] = None
    avatar_url: Optional[str] = None
    created_at: datetime
    is_face_registered: bool = False

    @model_validator(mode="before")
    @classmethod
    def compute_face_registered(cls, data):
        """Set is_face_registered based on whether face_encoding exists."""
        # Handle both dict and ORM object
        if isinstance(data, dict):
            encoding = data.get("face_encoding")
        else:
            encoding = getattr(data, "face_encoding", None)
        if isinstance(data, dict):
            data["is_face_registered"] = bool(encoding)
        else:
            # For ORM objects, we can't mutate; Pydantic will handle it
            pass
        return data


class UserUpdate(BaseModel):
    """PATCH /api/users/me"""
    full_name: Optional[str] = Field(None, min_length=2, max_length=255)
    email: Optional[EmailStr] = None


class UserRoleUpdate(BaseModel):
    """PATCH /api/admin/users/{id}/role"""
    role: str = Field(..., pattern=r"^(user|vice_admin|admin)$")


class UserStatusUpdate(BaseModel):
    """PATCH /api/admin/users/{id}/status"""
    is_active: bool


# ═══════════════════════════════════════════════════════════════════════════════
#  SESSION
# ═══════════════════════════════════════════════════════════════════════════════

class SessionOut(BaseModel):
    """Active session response."""
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    user_id: uuid.UUID
    ip_address: Optional[str] = None
    user_agent: Optional[str] = None
    is_active: bool
    created_at: datetime
    expires_at: datetime


# ═══════════════════════════════════════════════════════════════════════════════
#  BANK ACCOUNT
# ═══════════════════════════════════════════════════════════════════════════════

class AccountCreate(BaseModel):
    """POST /api/accounts/"""
    account_number: str = Field(..., min_length=8, max_length=34)
    bank_name: str = Field(..., min_length=2, max_length=255)
    ifsc_code: Optional[str] = Field(None, max_length=11, pattern=r"^[A-Z]{4}0[A-Z0-9]{6}$")
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
    ifsc_code: Optional[str] = None
    balance: Decimal
    currency: str
    is_primary: bool
    is_verified: bool = False
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
    challenge_sequence: Optional[list[str]] = None


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


# ═══════════════════════════════════════════════════════════════════════════════
#  ADMIN DASHBOARD
# ═══════════════════════════════════════════════════════════════════════════════

class DashboardStats(BaseModel):
    """GET /api/admin/dashboard"""
    total_users: int
    active_users: int
    total_transactions: int
    successful_transactions: int
    failed_transactions: int
    pending_transactions: int
    active_sessions: int
    total_volume: Decimal = Decimal("0.00")


class AuditLogOut(BaseModel):
    """Audit log entry."""
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    user_id: Optional[uuid.UUID] = None
    action: str
    target_type: Optional[str] = None
    target_id: Optional[str] = None
    ip_address: Optional[str] = None
    details: Optional[dict] = None
    created_at: datetime
