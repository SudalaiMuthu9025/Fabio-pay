"""
Fabio Backend — Auth Router
=============================
POST /api/auth/register  — create a new user (+ default SecuritySettings)
POST /api/auth/login     — authenticate and return JWT
"""

from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth import create_access_token, hash_password, hash_pin, verify_password
from app.database import get_db
from app.models import SecuritySettings, User
from app.schemas import Token, UserLogin, UserOut, UserRegister

router = APIRouter(prefix="/api/auth", tags=["Auth"])


# ── Register ──────────────────────────────────────────────────────────────────
@router.post(
    "/register",
    response_model=UserOut,
    status_code=status.HTTP_201_CREATED,
    summary="Register a new Fabio user",
)
async def register(body: UserRegister, db: AsyncSession = Depends(get_db)):
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
        hashed_password=hash_password(body.password),
    )
    db.add(user)
    await db.flush()  # populate user.id before creating settings

    # Create default security settings
    sec = SecuritySettings(
        user_id=user.id,
        pin_hash=hash_pin(body.pin),
    )
    db.add(sec)
    await db.flush()

    return user


# ── Login ─────────────────────────────────────────────────────────────────────
@router.post(
    "/login",
    response_model=Token,
    summary="Authenticate and receive a JWT",
)
async def login(body: UserLogin, db: AsyncSession = Depends(get_db)):
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

    token = create_access_token(user_id=str(user.id), role=user.role.value)
    return Token(access_token=token)
