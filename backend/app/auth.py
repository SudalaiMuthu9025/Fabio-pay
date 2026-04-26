"""
Fabio Backend — Authentication & JWT Utilities
================================================
JWT token auth, password hashing (Argon2), and PIN hashing.
"""

from __future__ import annotations

from datetime import datetime, timedelta, timezone
from typing import Callable

from fastapi import Depends, HTTPException, Request, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from jose import JWTError, jwt
from passlib.context import CryptContext
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.database import get_db
from app.models import User, UserRole

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
#  JWT Token Creation & Verification
# ═══════════════════════════════════════════════════════════════════════════════

def create_access_token(user_id: str, email: str, role: str) -> str:
    """
    Create a JWT access token with user claims.
    """
    expire = datetime.now(timezone.utc) + timedelta(
        minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES
    )
    payload = {
        "sub": str(user_id),
        "email": email,
        "role": role,
        "exp": expire,
        "iat": datetime.now(timezone.utc),
    }
    return jwt.encode(payload, settings.SECRET_KEY, algorithm=settings.JWT_ALGORITHM)


def decode_access_token(token: str) -> dict:
    """
    Decode and validate a JWT token. Raises JWTError on failure.
    """
    return jwt.decode(
        token, settings.SECRET_KEY, algorithms=[settings.JWT_ALGORITHM]
    )


# ── Bearer Token Extraction ──────────────────────────────────────────────────
bearer_scheme = HTTPBearer(auto_error=False)


# ── FastAPI Dependencies ──────────────────────────────────────────────────────

async def get_current_user(
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer_scheme),
    db: AsyncSession = Depends(get_db),
) -> User:
    """
    Dependency: extract Bearer token → decode JWT → return ORM user object.
    Raises 401 if invalid.
    """
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Could not validate credentials",
        headers={"WWW-Authenticate": "Bearer"},
    )

    if credentials is None:
        raise credentials_exception

    token = credentials.credentials

    try:
        payload = decode_access_token(token)
        user_id: str = payload.get("sub")
        if user_id is None:
            raise credentials_exception
    except JWTError:
        raise credentials_exception

    result = await db.execute(select(User).where(User.id == user_id))
    user = result.scalar_one_or_none()

    if user is None or not user.is_active:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="User not found or inactive",
        )
    return user


def require_role(*required_roles: UserRole) -> Callable:
    """
    RBAC dependency factory.

    Usage:
        @router.get("/admin-only", dependencies=[Depends(require_role(UserRole.ADMIN))])
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
