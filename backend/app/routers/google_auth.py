"""
Fabio Backend — Google OAuth Router
=====================================
POST /api/auth/google  — Authenticate with Google ID token
"""

from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, Request, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth import create_session
from app.config import settings
from app.database import get_db
from app.models import AuditLog, SecuritySettings, User
from app.schemas import GoogleAuthRequest, SessionToken

router = APIRouter(prefix="/api/auth", tags=["Google Auth"])


async def _verify_google_token(id_token: str) -> dict:
    """
    Verify a Google ID token and return the user info.
    Uses google.oauth2.id_token for verification.
    """
    try:
        from google.oauth2 import id_token as google_id_token
        from google.auth.transport import requests as google_requests

        idinfo = google_id_token.verify_oauth2_token(
            id_token,
            google_requests.Request(),
            settings.GOOGLE_CLIENT_ID,
        )

        if idinfo["iss"] not in ("accounts.google.com", "https://accounts.google.com"):
            raise ValueError("Wrong issuer")

        return {
            "google_id": idinfo["sub"],
            "email": idinfo.get("email", ""),
            "full_name": idinfo.get("name", ""),
            "avatar_url": idinfo.get("picture", ""),
            "email_verified": idinfo.get("email_verified", False),
        }
    except ValueError as e:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=f"Invalid Google token: {str(e)}",
        )
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=f"Google authentication failed: {str(e)}",
        )


@router.post(
    "/google",
    response_model=SessionToken,
    summary="Authenticate with Google",
)
async def google_auth(
    body: GoogleAuthRequest,
    request: Request,
    db: AsyncSession = Depends(get_db),
):
    """
    Authenticate using a Google ID token.
    - If user exists with this Google ID → log in
    - If user exists with same email → link Google account
    - If new user → create account
    """
    if not settings.GOOGLE_CLIENT_ID:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Google authentication is not configured",
        )

    google_info = await _verify_google_token(body.id_token)

    # 1. Check if user exists with this Google ID
    result = await db.execute(
        select(User).where(User.google_id == google_info["google_id"])
    )
    user = result.scalar_one_or_none()

    if user is None:
        # 2. Check if user exists with same email
        result = await db.execute(
            select(User).where(User.email == google_info["email"])
        )
        user = result.scalar_one_or_none()

        if user is not None:
            # Link Google account to existing user
            user.google_id = google_info["google_id"]
            if not user.avatar_url:
                user.avatar_url = google_info["avatar_url"]
            await db.flush()

            # Audit log
            audit = AuditLog(
                user_id=user.id,
                action="google.link",
                target_type="user",
                target_id=str(user.id),
                ip_address=request.client.host if request.client else None,
                details={"google_id": google_info["google_id"]},
            )
            db.add(audit)
        else:
            # 3. Create new user from Google account
            user = User(
                email=google_info["email"],
                full_name=google_info["full_name"],
                google_id=google_info["google_id"],
                avatar_url=google_info["avatar_url"],
                hashed_password=None,  # Google-only user, no password
            )
            db.add(user)
            await db.flush()

            # Create default security settings with a random PIN
            # (user should set their own PIN later for transactions)
            import secrets
            temp_pin = str(secrets.randbelow(9000) + 1000)  # 4-digit random
            from app.auth import hash_pin
            sec = SecuritySettings(
                user_id=user.id,
                pin_hash=hash_pin(temp_pin),
            )
            db.add(sec)

            # Audit log
            audit = AuditLog(
                user_id=user.id,
                action="user.register.google",
                target_type="user",
                target_id=str(user.id),
                ip_address=request.client.host if request.client else None,
            )
            db.add(audit)
            await db.flush()

    if not user.is_active:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Account is deactivated",
        )

    token = await create_session(user, db, request)
    return SessionToken(session_token=token)
