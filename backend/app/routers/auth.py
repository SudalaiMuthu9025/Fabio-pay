"""
Fabio Backend — Auth Router
=============================
POST /auth/register   — create a new user
POST /auth/login      — authenticate and return JWT
GET  /auth/me         — get current user profile
POST /auth/set-pin    — set 4-digit transaction PIN
"""

from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth import (
    create_access_token,
    get_current_user,
    hash_password,
    hash_pin,
    verify_password,
)
from app.database import get_db
from app.models import User
from app.schemas import (
    SetPinRequest,
    TokenResponse,
    UserLogin,
    UserOut,
    UserRegister,
)

router = APIRouter(prefix="/auth", tags=["Auth"])


# ── Register ──────────────────────────────────────────────────────────────────
@router.post(
    "/register",
    response_model=UserOut,
    status_code=status.HTTP_201_CREATED,
    summary="Register a new Fabio user",
)
async def register(
    body: UserRegister,
    db: AsyncSession = Depends(get_db),
):
    try:
        # Check duplicate email
        exists = await db.execute(select(User).where(User.email == body.email))
        if exists.scalar_one_or_none():
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="Email already registered",
            )

        # Create user
        user = User(
            email=body.email,
            full_name=body.full_name,
            phone=body.phone,
            hashed_password=hash_password(body.password),
        )
        db.add(user)
        await db.flush()
        await db.refresh(user)

        return _user_to_out(user)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Registration error: {type(e).__name__}: {str(e)}",
        )


# ── Login ─────────────────────────────────────────────────────────────────────
@router.post(
    "/login",
    response_model=TokenResponse,
    summary="Authenticate and receive a JWT token",
)
async def login(
    body: UserLogin,
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(select(User).where(User.email == body.email))
    user = result.scalar_one_or_none()

    if user is None or not verify_password(body.password, user.hashed_password):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid email or password",
        )

    if not user.is_active:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Account is deactivated",
        )

    token = create_access_token(
        user_id=str(user.id),
        email=user.email,
        role=user.role.value,
    )
    return TokenResponse(access_token=token)


# ── Me ────────────────────────────────────────────────────────────────────────
@router.get(
    "/me",
    response_model=UserOut,
    summary="Get current user profile",
)
async def get_me(
    current_user: User = Depends(get_current_user),
):
    return _user_to_out(current_user)


# ── Set PIN ───────────────────────────────────────────────────────────────────
@router.post(
    "/set-pin",
    response_model=UserOut,
    summary="Set 4-digit transaction PIN",
)
async def set_pin(
    body: SetPinRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    current_user.pin_hash = hash_pin(body.pin)
    await db.flush()
    return _user_to_out(current_user)


# ── Helper ────────────────────────────────────────────────────────────────────
def _user_to_out(user: User) -> UserOut:
    """Convert ORM User to UserOut with computed fields."""
    return UserOut(
        id=user.id,
        email=user.email,
        full_name=user.full_name,
        phone=user.phone,
        role=user.role.value,
        is_active=user.is_active,
        is_face_registered=user.face_embedding is not None,
        has_pin=user.pin_hash is not None,
        has_bank_account=len(user.bank_accounts) > 0 if user.bank_accounts else False,
        created_at=user.created_at,
    )
