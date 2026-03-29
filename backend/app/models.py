"""
Fabio Backend — SQLAlchemy ORM Models
======================================
Tables: users, bank_accounts, security_settings, transaction_logs.

Design choices
--------------
* **UUID primary keys**  — prevents sequential-ID enumeration (FinTech best practice).
* **Enum columns**       — enforces data integrity at the DB level for roles,
                           auth methods, and transaction statuses.
* **JSON column**        — `challenge_sequence` stores the biometric challenge
                           (e.g. ["Blink", "Smile", "Left"]) for full audit trail.
* **Numeric(15, 2)**     — cent-precise money storage without floating-point drift.
"""

from __future__ import annotations

import enum
import uuid
from datetime import datetime
from decimal import Decimal

from sqlalchemy import (
    Boolean,
    DateTime,
    Enum,
    ForeignKey,
    Integer,
    JSON,
    Numeric,
    String,
    Text,
    func,
)
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base


# ═══════════════════════════════════════════════════════════════════════════════
#  ENUM Types
# ═══════════════════════════════════════════════════════════════════════════════

class UserRole(str, enum.Enum):
    """RBAC roles — `user` can manage own accounts; `admin` views system logs."""
    USER = "user"
    ADMIN = "admin"


class AuthMethod(str, enum.Enum):
    """How a transaction was authenticated."""
    PIN = "pin"
    BIOMETRIC = "biometric"


class TransactionStatus(str, enum.Enum):
    """Lifecycle of a single transfer."""
    PENDING = "pending"
    SUCCESS = "success"
    FAILED = "failed"


# ═══════════════════════════════════════════════════════════════════════════════
#  USERS
# ═══════════════════════════════════════════════════════════════════════════════

class User(Base):
    """
    Core identity table.

    Relationships
    -------------
    * 1 : N  → BankAccount
    * 1 : 1  → SecuritySettings
    * 1 : N  → TransactionLog
    """

    __tablename__ = "users"

    # ── Primary Key ───────────────────────────────────────────────────────
    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        primary_key=True,
        default=uuid.uuid4,
    )

    # ── Identity Fields ───────────────────────────────────────────────────
    email: Mapped[str] = mapped_column(
        String(255), unique=True, index=True, nullable=False
    )
    full_name: Mapped[str] = mapped_column(String(255), nullable=False)
    hashed_password: Mapped[str] = mapped_column(Text, nullable=False)

    # ── RBAC ──────────────────────────────────────────────────────────────
    role: Mapped[UserRole] = mapped_column(
        Enum(UserRole, name="user_role", create_constraint=True),
        default=UserRole.USER,
        nullable=False,
    )
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)

    # ── Timestamps ────────────────────────────────────────────────────────
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        onupdate=func.now(),
        nullable=False,
    )

    # ── Relationships ─────────────────────────────────────────────────────
    bank_accounts: Mapped[list["BankAccount"]] = relationship(
        back_populates="owner",
        cascade="all, delete-orphan",
        lazy="selectin",
    )
    security_settings: Mapped["SecuritySettings | None"] = relationship(
        back_populates="user",
        cascade="all, delete-orphan",
        uselist=False,
        lazy="selectin",
    )
    transaction_logs: Mapped[list["TransactionLog"]] = relationship(
        back_populates="user",
        cascade="all, delete-orphan",
        lazy="selectin",
    )

    def __repr__(self) -> str:
        return f"<User {self.email!r} role={self.role.value}>"


# ═══════════════════════════════════════════════════════════════════════════════
#  BANK ACCOUNTS
# ═══════════════════════════════════════════════════════════════════════════════

class BankAccount(Base):
    """
    A user may have multiple bank accounts; one can be marked `is_primary`.

    Relationships
    -------------
    * N : 1  → User (owner)
    * 1 : N  → TransactionLog (as source account)
    """

    __tablename__ = "bank_accounts"

    # ── Primary Key ───────────────────────────────────────────────────────
    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        primary_key=True,
        default=uuid.uuid4,
    )

    # ── Foreign Key ───────────────────────────────────────────────────────
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )

    # ── Account Details ───────────────────────────────────────────────────
    account_number: Mapped[str] = mapped_column(
        String(34), unique=True, nullable=False  # IBAN max length = 34
    )
    bank_name: Mapped[str] = mapped_column(String(255), nullable=False)
    balance: Mapped[Decimal] = mapped_column(
        Numeric(15, 2), default=Decimal("0.00"), nullable=False
    )
    currency: Mapped[str] = mapped_column(
        String(3), default="INR", nullable=False  # ISO 4217
    )
    is_primary: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)

    # ── Timestamps ────────────────────────────────────────────────────────
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        onupdate=func.now(),
        nullable=False,
    )

    # ── Relationships ─────────────────────────────────────────────────────
    owner: Mapped["User"] = relationship(back_populates="bank_accounts")
    outgoing_transactions: Mapped[list["TransactionLog"]] = relationship(
        back_populates="from_account",
        cascade="all, delete-orphan",
        lazy="selectin",
    )

    def __repr__(self) -> str:
        return f"<BankAccount {self.account_number!r} bank={self.bank_name!r}>"


# ═══════════════════════════════════════════════════════════════════════════════
#  SECURITY SETTINGS (Risk-Based Authentication Config)
# ═══════════════════════════════════════════════════════════════════════════════

class SecuritySettings(Base):
    """
    Per-user security configuration.

    `threshold_amount` drives the risk-based auth flow:
      • transfer < threshold → standard PIN
      • transfer ≥ threshold → Fabio Active Liveness (biometric challenge)

    Relationships
    -------------
    * 1 : 1  → User
    """

    __tablename__ = "security_settings"

    # ── Primary Key ───────────────────────────────────────────────────────
    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        primary_key=True,
        default=uuid.uuid4,
    )

    # ── Foreign Key (unique → 1:1) ───────────────────────────────────────
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        unique=True,
        nullable=False,
        index=True,
    )

    # ── Threshold for Risk-Based Auth ─────────────────────────────────────
    threshold_amount: Mapped[Decimal] = mapped_column(
        Numeric(15, 2),
        default=Decimal("10000.00"),  # Default: ₹10,000
        nullable=False,
    )

    # ── PIN Auth ──────────────────────────────────────────────────────────
    pin_hash: Mapped[str] = mapped_column(Text, nullable=False)

    # ── Biometric Flags ───────────────────────────────────────────────────
    biometric_enabled: Mapped[bool] = mapped_column(
        Boolean, default=True, nullable=False
    )

    # ── Lockout Policy ────────────────────────────────────────────────────
    max_attempts: Mapped[int] = mapped_column(
        Integer, default=5, nullable=False
    )
    lockout_duration_minutes: Mapped[int] = mapped_column(
        Integer, default=30, nullable=False  # minutes
    )
    failed_attempts: Mapped[int] = mapped_column(
        Integer, default=0, nullable=False
    )
    locked_until: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True, default=None
    )

    # ── Timestamps ────────────────────────────────────────────────────────
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        onupdate=func.now(),
        nullable=False,
    )

    # ── Relationship ──────────────────────────────────────────────────────
    user: Mapped["User"] = relationship(back_populates="security_settings")

    def __repr__(self) -> str:
        return (
            f"<SecuritySettings user_id={self.user_id!r} "
            f"threshold={self.threshold_amount}>"
        )


# ═══════════════════════════════════════════════════════════════════════════════
#  TRANSACTION LOGS (Audit Trail)
# ═══════════════════════════════════════════════════════════════════════════════

class TransactionLog(Base):
    """
    Immutable audit record for every transfer attempt.

    Stores the authentication method used, biometric challenge sequence,
    risk score, and final status for compliance & fraud analysis.

    Relationships
    -------------
    * N : 1  → User
    * N : 1  → BankAccount (source)
    """

    __tablename__ = "transaction_logs"

    # ── Primary Key ───────────────────────────────────────────────────────
    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        primary_key=True,
        default=uuid.uuid4,
    )

    # ── Foreign Keys ──────────────────────────────────────────────────────
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    from_account_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("bank_accounts.id", ondelete="SET NULL"),
        nullable=True,
        index=True,
    )
    # Destination may be external — store as plain string, no FK.
    to_account_identifier: Mapped[str | None] = mapped_column(
        String(34), nullable=True
    )

    # ── Transfer Details ──────────────────────────────────────────────────
    amount: Mapped[Decimal] = mapped_column(Numeric(15, 2), nullable=False)
    currency: Mapped[str] = mapped_column(
        String(3), default="INR", nullable=False
    )
    description: Mapped[str | None] = mapped_column(Text, nullable=True)

    # ── Authentication & Security ─────────────────────────────────────────
    auth_method: Mapped[AuthMethod] = mapped_column(
        Enum(AuthMethod, name="auth_method", create_constraint=True),
        nullable=False,
    )
    status: Mapped[TransactionStatus] = mapped_column(
        Enum(TransactionStatus, name="transaction_status", create_constraint=True),
        default=TransactionStatus.PENDING,
        nullable=False,
    )
    risk_score: Mapped[Decimal | None] = mapped_column(
        Numeric(5, 2), nullable=True  # 0.00 – 100.00
    )

    # ── Biometric Challenge Audit ─────────────────────────────────────────
    # Stores the full challenge sequence + per-action results.
    # Example: {"sequence": ["Blink","Smile","Left"], "results": [true,true,true]}
    challenge_sequence: Mapped[dict | None] = mapped_column(
        JSON, nullable=True, default=None
    )

    # ── Device / Network Metadata ─────────────────────────────────────────
    ip_address: Mapped[str | None] = mapped_column(String(45), nullable=True)
    user_agent: Mapped[str | None] = mapped_column(Text, nullable=True)

    # ── Timestamps ────────────────────────────────────────────────────────
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )

    # ── Relationships ─────────────────────────────────────────────────────
    user: Mapped["User"] = relationship(back_populates="transaction_logs")
    from_account: Mapped["BankAccount | None"] = relationship(
        back_populates="outgoing_transactions"
    )

    def __repr__(self) -> str:
        return (
            f"<TransactionLog {self.id!r} amount={self.amount} "
            f"status={self.status.value}>"
        )
