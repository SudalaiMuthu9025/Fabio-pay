"""
Fabio Backend — SQLAlchemy ORM Models
======================================
Tables: users, bank_accounts, security_settings, transaction_logs,
        sessions, audit_logs.

Design choices
--------------
* **UUID primary keys**  — prevents sequential-ID enumeration (FinTech best practice).
* **Enum columns**       — enforces data integrity at the DB level for roles,
                           auth methods, and transaction statuses.
* **JSON column**        — `challenge_sequence` stores the biometric challenge
                           (e.g. ["Blink", "Smile", "Left"]) for full audit trail.
* **Numeric(15, 2)**     — cent-precise money storage without floating-point drift.
* **Session table**      — server-side session management (replaces JWT).
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
    """RBAC roles — three tiers of access."""
    USER = "user"
    VICE_ADMIN = "vice_admin"
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
    * 1 : N  → Session
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
    hashed_password: Mapped[str | None] = mapped_column(Text, nullable=True)

    # ── Google OAuth ─────────────────────────────────────────────────────
    google_id: Mapped[str | None] = mapped_column(
        String(255), unique=True, nullable=True, index=True
    )
    avatar_url: Mapped[str | None] = mapped_column(Text, nullable=True)

    # ── Liveness / Face Verification ─────────────────────────────────────
    liveness_verified: Mapped[bool] = mapped_column(
        Boolean, default=False, nullable=False,
        doc="Whether the user has passed face liveness verification"
    )
    last_liveness_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True,
        doc="Timestamp of last successful liveness verification"
    )
    liveness_count: Mapped[int] = mapped_column(
        Integer, default=0, nullable=False,
        doc="Total number of successful liveness verifications"
    )
    face_encoding: Mapped[list[float] | None] = mapped_column(
        JSON, nullable=True,
        doc="MediaPipe Face Mesh normalized landmark vector for 1:1 face verification"
    )

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
    sessions: Mapped[list["Session"]] = relationship(
        back_populates="user",
        cascade="all, delete-orphan",
        lazy="noload",
    )

    def __repr__(self) -> str:
        return f"<User {self.email!r} role={self.role.value}>"


# ═══════════════════════════════════════════════════════════════════════════════
#  SESSIONS (Server-Side Session Management — replaces JWT)
# ═══════════════════════════════════════════════════════════════════════════════

class Session(Base):
    """
    Server-side session record. Each login creates a session row.
    The token is signed with HMAC-SHA256 and the hash is stored here.
    """

    __tablename__ = "sessions"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        primary_key=True,
        default=uuid.uuid4,
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    token_hash: Mapped[str] = mapped_column(Text, nullable=False, unique=True)
    ip_address: Mapped[str | None] = mapped_column(String(45), nullable=True)
    user_agent: Mapped[str | None] = mapped_column(Text, nullable=True)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    expires_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False
    )

    # ── Relationship ──────────────────────────────────────────────────────
    user: Mapped["User"] = relationship(back_populates="sessions")

    def __repr__(self) -> str:
        return f"<Session {self.id!r} user={self.user_id!r} active={self.is_active}>"


# ═══════════════════════════════════════════════════════════════════════════════
#  AUDIT LOGS
# ═══════════════════════════════════════════════════════════════════════════════

class AuditLog(Base):
    """
    Immutable audit record for security-relevant actions.
    Tracks logins, role changes, session terminations, etc.
    """

    __tablename__ = "audit_logs"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        primary_key=True,
        default=uuid.uuid4,
    )
    user_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="SET NULL"),
        nullable=True,
        index=True,
    )
    action: Mapped[str] = mapped_column(String(100), nullable=False, index=True)
    target_type: Mapped[str | None] = mapped_column(String(50), nullable=True)
    target_id: Mapped[str | None] = mapped_column(String(255), nullable=True)
    ip_address: Mapped[str | None] = mapped_column(String(45), nullable=True)
    details: Mapped[dict | None] = mapped_column(JSON, nullable=True)

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )

    def __repr__(self) -> str:
        return f"<AuditLog {self.action!r} user={self.user_id!r}>"


# ═══════════════════════════════════════════════════════════════════════════════
#  BANK ACCOUNTS
# ═══════════════════════════════════════════════════════════════════════════════

class BankAccount(Base):
    """
    A user may have multiple bank accounts; one can be marked `is_primary`.
    """

    __tablename__ = "bank_accounts"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        primary_key=True,
        default=uuid.uuid4,
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    account_number: Mapped[str] = mapped_column(
        String(34), unique=True, nullable=False
    )
    bank_name: Mapped[str] = mapped_column(String(255), nullable=False)
    ifsc_code: Mapped[str | None] = mapped_column(
        String(11), nullable=True,
        doc="IFSC code for Indian bank branches"
    )
    balance: Mapped[Decimal] = mapped_column(
        Numeric(15, 2), default=Decimal("0.00"), nullable=False
    )
    currency: Mapped[str] = mapped_column(
        String(3), default="INR", nullable=False
    )
    is_primary: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    is_verified: Mapped[bool] = mapped_column(
        Boolean, default=False, nullable=False,
        doc="Admin-verified bank account"
    )

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        onupdate=func.now(),
        nullable=False,
    )

    owner: Mapped["User"] = relationship(back_populates="bank_accounts")
    outgoing_transactions: Mapped[list["TransactionLog"]] = relationship(
        back_populates="from_account",
        cascade="all, delete-orphan",
        lazy="selectin",
    )

    def __repr__(self) -> str:
        return f"<BankAccount {self.account_number!r} bank={self.bank_name!r}>"


# ═══════════════════════════════════════════════════════════════════════════════
#  SECURITY SETTINGS
# ═══════════════════════════════════════════════════════════════════════════════

class SecuritySettings(Base):
    """
    Per-user security configuration.
    threshold_amount drives risk-based auth:
      • transfer < threshold → standard PIN
      • transfer ≥ threshold → biometric challenge
    """

    __tablename__ = "security_settings"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        primary_key=True,
        default=uuid.uuid4,
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        unique=True,
        nullable=False,
        index=True,
    )
    threshold_amount: Mapped[Decimal] = mapped_column(
        Numeric(15, 2),
        default=Decimal("10000.00"),
        nullable=False,
    )
    pin_hash: Mapped[str] = mapped_column(Text, nullable=False)
    biometric_enabled: Mapped[bool] = mapped_column(
        Boolean, default=True, nullable=False
    )
    max_attempts: Mapped[int] = mapped_column(Integer, default=5, nullable=False)
    lockout_duration_minutes: Mapped[int] = mapped_column(
        Integer, default=30, nullable=False
    )
    failed_attempts: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    locked_until: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True, default=None
    )

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        onupdate=func.now(),
        nullable=False,
    )

    user: Mapped["User"] = relationship(back_populates="security_settings")

    def __repr__(self) -> str:
        return (
            f"<SecuritySettings user_id={self.user_id!r} "
            f"threshold={self.threshold_amount}>"
        )


# ═══════════════════════════════════════════════════════════════════════════════
#  TRANSACTION LOGS
# ═══════════════════════════════════════════════════════════════════════════════

class TransactionLog(Base):
    """
    Immutable audit record for every transfer attempt.
    """

    __tablename__ = "transaction_logs"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        primary_key=True,
        default=uuid.uuid4,
    )
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
    to_account_identifier: Mapped[str | None] = mapped_column(
        String(34), nullable=True
    )
    amount: Mapped[Decimal] = mapped_column(Numeric(15, 2), nullable=False)
    currency: Mapped[str] = mapped_column(
        String(3), default="INR", nullable=False
    )
    description: Mapped[str | None] = mapped_column(Text, nullable=True)
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
        Numeric(5, 2), nullable=True
    )
    challenge_sequence: Mapped[dict | None] = mapped_column(
        JSON, nullable=True, default=None
    )
    ip_address: Mapped[str | None] = mapped_column(String(45), nullable=True)
    user_agent: Mapped[str | None] = mapped_column(Text, nullable=True)

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )

    user: Mapped["User"] = relationship(back_populates="transaction_logs")
    from_account: Mapped["BankAccount | None"] = relationship(
        back_populates="outgoing_transactions"
    )

    def __repr__(self) -> str:
        return (
            f"<TransactionLog {self.id!r} amount={self.amount} "
            f"status={self.status.value}>"
        )
