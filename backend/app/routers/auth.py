"""
Fabio Backend — Auth Router
=============================
POST /api/auth/register  — create a new user (+ default SecuritySettings)
POST /api/auth/login     — authenticate and return session token
POST /api/auth/logout    — revoke current session
GET  /api/auth/sessions  — list active sessions for current user
DELETE /api/auth/sessions/{id} — revoke specific session
"""

from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, Request, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth import (
    create_session,
    get_current_user,
    hash_password,
    hash_pin,
    revoke_session,
    revoke_session_by_id,
    verify_password,
)
from app.database import get_db
from app.models import AuditLog, SecuritySettings, Session, User
from app.schemas import SessionOut, SessionToken, UserLogin, UserOut, UserRegister

router = APIRouter(prefix="/api/auth", tags=["Auth"])


# ── Register ──────────────────────────────────────────────────────────────────
@router.post(
    "/register",
    response_model=UserOut,
    status_code=status.HTTP_201_CREATED,
    summary="Register a new Fabio user",
)
async def register(
    body: UserRegister,
    request: Request,
    db: AsyncSession = Depends(get_db),
):
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
    await db.flush()

    # Create default security settings
    sec = SecuritySettings(
        user_id=user.id,
        pin_hash=hash_pin(body.pin),
    )
    db.add(sec)

    # Audit log
    audit = AuditLog(
        user_id=user.id,
        action="user.register",
        target_type="user",
        target_id=str(user.id),
        ip_address=request.client.host if request.client else None,
    )
    db.add(audit)

    await db.flush()
    return user


# ── Login ─────────────────────────────────────────────────────────────────────
@router.post(
    "/login",
    response_model=SessionToken,
    summary="Authenticate and receive a session token",
)
async def login(
    body: UserLogin,
    request: Request,
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(select(User).where(User.email == body.email))
    user = result.scalar_one_or_none()

    if user is None or not user.hashed_password or not verify_password(body.password, user.hashed_password):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid email or password",
        )

    if not user.is_active:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Account is deactivated",
        )

    token = await create_session(user, db, request)
    return SessionToken(session_token=token)


# ── Logout ────────────────────────────────────────────────────────────────────
@router.post(
    "/logout",
    status_code=status.HTTP_200_OK,
    summary="Revoke current session",
)
async def logout(
    request: Request,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    # Extract token from Authorization header
    auth_header = request.headers.get("authorization", "")
    if auth_header.startswith("Bearer "):
        token = auth_header[7:]
        await revoke_session(token, db)

    # Audit log
    audit = AuditLog(
        user_id=current_user.id,
        action="user.logout",
        ip_address=request.client.host if request.client else None,
    )
    db.add(audit)
    await db.flush()

    return {"message": "Logged out successfully"}


# ── List Active Sessions ─────────────────────────────────────────────────────
@router.get(
    "/sessions",
    response_model=list[SessionOut],
    summary="List your active sessions",
)
async def list_sessions(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(Session)
        .where(Session.user_id == current_user.id, Session.is_active == True)
        .order_by(Session.created_at.desc())
    )
    return result.scalars().all()


# ── Revoke Specific Session ──────────────────────────────────────────────────
@router.delete(
    "/sessions/{session_id}",
    status_code=status.HTTP_200_OK,
    summary="Revoke a specific session",
)
async def revoke_specific_session(
    session_id: str,
    request: Request,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    # Ensure the session belongs to the user
    result = await db.execute(
        select(Session).where(
            Session.id == session_id,
            Session.user_id == current_user.id,
            Session.is_active == True,
        )
    )
    session = result.scalar_one_or_none()
    if session is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Session not found",
        )

    session.is_active = False

    # Audit log
    audit = AuditLog(
        user_id=current_user.id,
        action="session.revoke",
        target_type="session",
        target_id=session_id,
        ip_address=request.client.host if request.client else None,
    )
    db.add(audit)
    await db.flush()

    return {"message": "Session revoked"}
