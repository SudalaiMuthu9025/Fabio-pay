"""
Fabio Backend — Face Router
=============================
POST /face/register  — register face embedding (permanent)
POST /face/verify    — verify a live face image against stored embedding
"""

from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth import get_current_user
from app.config import settings
from app.database import get_db
from app.face_utils import extract_face_embedding, verify_face_match
from app.models import FaceEmbedding, User
from app.schemas import (
    FaceRegisterRequest,
    FaceRegisterResponse,
    FaceVerifyRequest,
    FaceVerifyResponse,
)

router = APIRouter(prefix="/face", tags=["Face"])


# ── Register Face ─────────────────────────────────────────────────────────────
@router.post(
    "/register",
    response_model=FaceRegisterResponse,
    summary="Register face embedding (permanent, never deleted)",
)
async def register_face(
    body: FaceRegisterRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    # Check if face already registered
    if current_user.face_embedding is not None:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Face already registered. Contact support to re-register.",
        )

    # Extract face embedding from image
    embedding = extract_face_embedding(body.image)
    if embedding is None:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="No face detected in the image. Please try again with a clear photo.",
        )

    # Store permanently
    face = FaceEmbedding(
        user_id=current_user.id,
        embedding=embedding,
    )
    db.add(face)
    await db.flush()

    return FaceRegisterResponse(
        success=True,
        message="Face registered successfully",
    )


# ── Verify Face ───────────────────────────────────────────────────────────────
@router.post(
    "/verify",
    response_model=FaceVerifyResponse,
    summary="Verify live face against stored embedding",
)
async def verify_face(
    body: FaceVerifyRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    # Check if face is registered
    if current_user.face_embedding is None:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="No face registered. Please register your face first.",
        )

    # Extract embedding from live image
    live_embedding = extract_face_embedding(body.image)
    if live_embedding is None:
        return FaceVerifyResponse(
            verified=False,
            message="No face detected in the live image. Please try again.",
        )

    # Compare against stored embedding
    is_match = verify_face_match(
        live_embedding=live_embedding,
        registered_embedding=current_user.face_embedding.embedding,
        threshold=settings.FACE_MATCH_THRESHOLD,
    )

    if is_match:
        return FaceVerifyResponse(
            verified=True,
            message="Face verification successful",
        )
    else:
        return FaceVerifyResponse(
            verified=False,
            message="Face does not match. Verification failed.",
        )
