"""
Fabio Backend — Face Router
=============================
POST /face/register  — register face embedding (permanent)
POST /face/verify    — verify a live face image against stored embedding
"""

from __future__ import annotations

import logging
import traceback

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import delete
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth import get_current_user
from app.config import settings
from app.database import get_db
from app.models import FaceEmbedding, User
from app.schemas import (
    FaceRegisterRequest,
    FaceRegisterResponse,
    FaceVerifyRequest,
    FaceVerifyResponse,
)

logger = logging.getLogger("fabio.face")
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
    logger.info(f"Face register request from user {current_user.id}")
    logger.info(f"Image payload size: {len(body.image)} chars")

    # If face already registered, delete old one and re-register
    if current_user.face_embedding is not None:
        logger.info("Face already registered — replacing existing embedding")
        await db.execute(
            delete(FaceEmbedding).where(
                FaceEmbedding.user_id == current_user.id
            )
        )
        await db.flush()

    # Extract face embedding from image
    try:
        from app.face_utils import extract_face_embedding
        embedding = extract_face_embedding(body.image)
    except Exception as e:
        logger.exception(f"MediaPipe face extraction crashed: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Face processing engine error: {str(e)}",
        )

    if embedding is None:
        logger.warning("No face detected in image")
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="No face detected in the image. Please try again with a clear, well-lit photo.",
        )

    logger.info(f"Face embedding extracted: {len(embedding)} dimensions")

    # Store permanently
    try:
        face = FaceEmbedding(
            user_id=current_user.id,
            embedding=embedding,
        )
        db.add(face)
        await db.flush()
    except Exception as e:
        logger.exception(f"Database error storing embedding: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to save face data: {str(e)}",
        )

    logger.info(f"Face registered successfully for user {current_user.id}")
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
    try:
        from app.face_utils import extract_face_embedding, verify_face_match
        live_embedding = extract_face_embedding(body.image)
    except Exception as e:
        logger.exception(f"MediaPipe verify crashed: {e}")
        return FaceVerifyResponse(
            verified=False,
            message=f"Face processing error: {str(e)}",
        )

    if live_embedding is None:
        return FaceVerifyResponse(
            verified=False,
            message="No face detected in the live image. Please try again.",
        )

    # Compare against stored embedding
    try:
        is_match = verify_face_match(
            live_embedding=live_embedding,
            registered_embedding=current_user.face_embedding.embedding,
            threshold=settings.FACE_MATCH_THRESHOLD,
        )
    except Exception as e:
        logger.exception(f"Face match comparison error: {e}")
        return FaceVerifyResponse(
            verified=False,
            message=f"Comparison error: {str(e)}",
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
