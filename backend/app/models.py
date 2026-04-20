"""
Fabio Backend — SQLAlchemy ORM Models
======================================
Tables: users, face_embeddings, bank_accounts, transactions.

Design choices:
* UUID primary keys — prevents sequential-ID enumeration.
* Separate face_embeddings table — permanent, never deleted on logout.
* Numeric(15, 2) — cent-precise money storage without floating-point drift.
* JWT auth — stateless, no sessions table needed.
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
    USER = "USER"
    ADMIN = "ADMIN"


class AuthMethod(str, enum.Enum):
    PIN = "PIN"
    BIOMETRIC = "BIOMETRIC"


class TransactionStatus(str, enum.Enum):
    PENDING = "PENDING"
    SUCCESS = "SUCCESS"
    FAILED = "FAILED"


# ═══════════════════════════════════════════════════════════════════════════════
#  USERS
# ═══════════════════════════════════════════════════════════════════════════════

class User(Base):
    """
    Core identity table.

    Relationships:
    * 1 : 1  → FaceEmbedding
    * 1 : N  → BankAccount
    * 1 : N  → Transaction
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
    phone: Mapped[str | None] = mapped_column(String(20), nullable=True)
    hashed_password: Mapped[str] = mapped_column(Text, nullable=False)

    # ── PIN (4-digit, Argon2 hashed) ─────────────────────────────────────
    pin_hash: Mapped[str | None] = mapped_column(Text, nullable=True)

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
    face_embedding: Mapped["FaceEmbedding | None"] = relationship(
        back_populates="user",
        cascade="all, delete-orphan",
        uselist=False,
        lazy="selectin",
    )
    bank_accounts: Mapped[list["BankAccount"]] = relationship(
        back_populates="owner",
        cascade="all, delete-orphan",
        lazy="selectin",
    )
    transactions: Mapped[list["Transaction"]] = relationship(
        back_populates="user",
        cascade="all, delete-orphan",
        lazy="noload",
    )

    def __repr__(self) -> str:
        return f"<User {self.email!r} role={self.role.value}>"


# ═══════════════════════════════════════════════════════════════════════════════
#  FACE EMBEDDINGS (Permanent — never deleted on logout)
# ═══════════════════════════════════════════════════════════════════════════════

class FaceEmbedding(Base):
    """
    Stores the user's face encoding as a JSON array of floats.
    One face per user. Permanent — never deleted on logout.
    """

    __tablename__ = "face_embeddings"

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
    embedding: Mapped[list] = mapped_column(
        JSON, nullable=False,
        doc="Face descriptor vector (float array) for 1:1 verification"
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

    # ── Relationship ──────────────────────────────────────────────────────
    user: Mapped["User"] = relationship(back_populates="face_embedding")

    def __repr__(self) -> str:
        return f"<FaceEmbedding user_id={self.user_id!r}>"


# ═══════════════════════════════════════════════════════════════════════════════
#  BANK ACCOUNTS
# ═══════════════════════════════════════════════════════════════════════════════

class BankAccount(Base):
    """
    A user's bank account for sending/receiving money.
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
    ifsc_code: Mapped[str] = mapped_column(
        String(11), nullable=False,
        doc="IFSC code for Indian bank branches"
    )
    account_holder_name: Mapped[str] = mapped_column(
        String(255), nullable=False
    )
    balance: Mapped[Decimal] = mapped_column(
        Numeric(15, 2), default=Decimal("10000.00"), nullable=False
    )
    currency: Mapped[str] = mapped_column(
        String(3), default="INR", nullable=False
    )
    is_primary: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )

    owner: Mapped["User"] = relationship(back_populates="bank_accounts")

    def __repr__(self) -> str:
        return f"<BankAccount {self.account_number!r}>"


# ═══════════════════════════════════════════════════════════════════════════════
#  TRANSACTIONS
# ═══════════════════════════════════════════════════════════════════════════════

class Transaction(Base):
    """
    Immutable record for every transfer attempt.
    """

    __tablename__ = "transactions"

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
    )
    to_account_identifier: Mapped[str] = mapped_column(
        String(34), nullable=False
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
    ip_address: Mapped[str | None] = mapped_column(String(45), nullable=True)

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )

    user: Mapped["User"] = relationship(back_populates="transactions")

    def __repr__(self) -> str:
        return (
            f"<Transaction {self.id!r} amount={self.amount} "
            f"status={self.status.value}>"
        )
