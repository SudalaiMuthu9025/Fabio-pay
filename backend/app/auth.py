"""
Fabio Backend — Authentication & Authorization Utilities
=========================================================
Session-token auth (replaces JWT), password hashing, and RBAC dependencies.

Security Model
--------------
1. User logs in → server generates a random 64-byte token
2. Token is signed with HMAC-SHA256 using SECRET_KEY
3. Format: base64(random_bytes).base64(hmac_signature)
4. Server stores SHA-256 hash of the full token in the sessions table
5. On each request, server verifies HMAC, then looks up session by hash
6. Sessions can be revoked, have TTL, and support device tracking
"""

from __future__ import annotations

import hashlib
import hmac
import os
import base64
from datetime import datetime, timedelta, timezone
from typing import Callable

from fastapi import Depends, HTTPException, Request, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from passlib.context import CryptContext
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.database import get_db
from app.models import AuditLog, Session, User, UserRole

# ── Password Hashing ─────────────────────────────────────────────────────────
pwd_context = CryptContext(schemes=["argon2"], deprecated="auto")


def hash_password(plain: str) -> str:
    """Return an Argon2 hash of the plain-text password."""
    return pwd_context.hash(plain)


def verify_password(plain: str, hashed: str) -> bool:
    """Check plain-text against Argon2 hash."""
    return pwd_context.verify(plain, hashed)


# ── PIN Hashing ──────────────────────────────────────────────────────────────
def hash_pin(pin: str) -> str:
    """Return an Argon2 hash of the numeric PIN."""
    return pwd_context.hash(pin)


def verify_pin(pin: str, hashed: str) -> bool:
    """Check plain-text PIN against Argon2 hash."""
    return pwd_context.verify(pin, hashed)


# ═══════════════════════════════════════════════════════════════════════════════
#  Session Token Creation & Verification
# ═══════════════════════════════════════════════════════════════════════════════

def _sign_token(raw_bytes: bytes) -> str:
    """Create HMAC-SHA256 signature of raw token bytes."""
    sig = hmac.new(
        settings.SECRET_KEY.encode("utf-8"),
        raw_bytes,
        hashlib.sha256,
    ).digest()
    return base64.urlsafe_b64encode(sig).decode("utf-8").rstrip("=")


def _hash_token(token_str: str) -> str:
    """SHA-256 hash of the full token string for DB storage."""
    return hashlib.sha256(token_str.encode("utf-8")).hexdigest()


def generate_session_token() -> str:
    """
    Generate a secure session token.
    Format: base64(random_64_bytes).hmac_signature
    """
    raw = os.urandom(64)
    raw_b64 = base64.urlsafe_b64encode(raw).decode("utf-8").rstrip("=")
    signature = _sign_token(raw)
    return f"{raw_b64}.{signature}"


def verify_token_signature(token: str) -> bool:
    """Verify the HMAC signature of a session token."""
    parts = token.split(".", 1)
    if len(parts) != 2:
        return False
    raw_b64, provided_sig = parts
    # Reconstruct the raw bytes (re-pad base64)
    padding = 4 - len(raw_b64) % 4
    if padding != 4:
        raw_b64_padded = raw_b64 + "=" * padding
    else:
        raw_b64_padded = raw_b64
    try:
        raw = base64.urlsafe_b64decode(raw_b64_padded)
    except Exception:
        return False
    expected_sig = _sign_token(raw)
    return hmac.compare_digest(provided_sig, expected_sig)


async def create_session(
    user: User,
    db: AsyncSession,
    request: Request | None = None,
) -> str:
    """
    Create a new server-side session for the user.
    Returns the session token string to send to the client.
    """
    token = generate_session_token()
    token_hash = _hash_token(token)

    ip_address = None
    user_agent = None
    if request:
        ip_address = request.client.host if request.client else None
        user_agent = request.headers.get("user-agent")

    session = Session(
        user_id=user.id,
        token_hash=token_hash,
        ip_address=ip_address,
        user_agent=user_agent,
        expires_at=datetime.now(timezone.utc) + timedelta(
            hours=settings.SESSION_EXPIRE_HOURS
        ),
    )
    db.add(session)

    # Audit log
    audit = AuditLog(
        user_id=user.id,
        action="user.login",
        target_type="session",
        target_id=str(session.id),
        ip_address=ip_address,
        details={"user_agent": user_agent},
    )
    db.add(audit)

    await db.flush()
    return token


async def revoke_session(token: str, db: AsyncSession) -> bool:
    """Revoke a session by its token. Returns True if found and revoked."""
    token_hash = _hash_token(token)
    result = await db.execute(
        select(Session).where(
            Session.token_hash == token_hash,
            Session.is_active == True,
        )
    )
    session = result.scalar_one_or_none()
    if session is None:
        return False
    session.is_active = False
    await db.flush()
    return True


async def revoke_session_by_id(session_id: str, db: AsyncSession) -> bool:
    """Revoke a session by its database ID. Returns True if found and revoked."""
    result = await db.execute(
        select(Session).where(Session.id == session_id, Session.is_active == True)
    )
    session = result.scalar_one_or_none()
    if session is None:
        return False
    session.is_active = False
    await db.flush()
    return True


# ── Bearer Token Extraction ──────────────────────────────────────────────────
bearer_scheme = HTTPBearer(auto_error=False)


# ── FastAPI Dependencies ──────────────────────────────────────────────────────

async def get_current_user(
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer_scheme),
    db: AsyncSession = Depends(get_db),
) -> User:
    """
    Dependency: extract Bearer token → verify signature → look up session
    → return ORM user object. Raises 401 if invalid.
    """
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Could not validate credentials",
        headers={"WWW-Authenticate": "Bearer"},
    )

    if credentials is None:
        raise credentials_exception

    token = credentials.credentials

    # 1. Verify HMAC signature
    if not verify_token_signature(token):
        raise credentials_exception

    # 2. Look up session by token hash
    token_hash = _hash_token(token)
    result = await db.execute(
        select(Session).where(
            Session.token_hash == token_hash,
            Session.is_active == True,
        )
    )
    session = result.scalar_one_or_none()

    if session is None:
        raise credentials_exception

    # 3. Check expiration
    if session.expires_at < datetime.now(timezone.utc):
        session.is_active = False
        await db.flush()
        raise credentials_exception

    # 4. Load user
    user_result = await db.execute(
        select(User).where(User.id == session.user_id)
    )
    user = user_result.scalar_one_or_none()

    if user is None or not user.is_active:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="User not found or inactive",
        )
    return user

async def get_user_from_token(token: str, db: AsyncSession) -> User | None:
    """Helper for WebSocket auth via query string. Returns None if invalid."""
    if not token or not verify_token_signature(token):
        return None

    token_hash = _hash_token(token)
    result = await db.execute(
        select(Session).where(
            Session.token_hash == token_hash,
            Session.is_active == True,
        )
    )
    session = result.scalar_one_or_none()

    if session is None or session.expires_at < datetime.now(timezone.utc):
        return None

    user_result = await db.execute(select(User).where(User.id == session.user_id))
    user = user_result.scalar_one_or_none()

    if user is None or not user.is_active:
        return None
    
    return user


def require_role(*required_roles: UserRole) -> Callable:
    """
    RBAC dependency factory. Accepts one or more roles.

    Usage:
        @router.get("/admin-only", dependencies=[Depends(require_role(UserRole.ADMIN))])
        @router.get("/staff", dependencies=[Depends(require_role(UserRole.ADMIN, UserRole.VICE_ADMIN))])
    """

    async def _role_checker(
        current_user: User = Depends(get_current_user),
    ) -> User:
        if current_user.role not in required_roles:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail=f"Requires one of: {', '.join(r.value for r in required_roles)}",
            )
        return current_user

    return _role_checker
