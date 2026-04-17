"""
Fabio Backend — Security Settings Router
==========================================
GET   /api/security/            — view own security settings
PATCH /api/security/            — update threshold, PIN, biometric toggle
POST  /api/security/register-face — register face embedding for 1:1 verification
POST  /api/security/verify-face   — verify a selfie against stored face data
GET   /api/security/face-status   — check if face is registered
"""

from __future__ import annotations

import base64

from fastapi import APIRouter, Depends, HTTPException, UploadFile, File, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth import get_current_user, hash_pin
from app.database import get_db
from app.face_recognition import extract_face_embedding_from_b64, verify_face_match
from app.models import User
from app.schemas import (
    FaceStatusResponse,
    FaceVerifyResponse,
    SecuritySettingsOut,
    SecuritySettingsUpdate,
)

router = APIRouter(prefix="/api/security", tags=["Security Settings"])


# ── Get Settings ──────────────────────────────────────────────────────────────
@router.get("/", response_model=SecuritySettingsOut, summary="View security settings")
async def get_security_settings(
    current_user: User = Depends(get_current_user),
):
    if current_user.security_settings is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Security settings not found",
        )
    return current_user.security_settings


# ── Update Settings ──────────────────────────────────────────────────────────
@router.patch("/", response_model=SecuritySettingsOut, summary="Update security settings")
async def update_security_settings(
    body: SecuritySettingsUpdate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    sec = current_user.security_settings
    if sec is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Security settings not found",
        )

    update_data = body.model_dump(exclude_unset=True)
    if not update_data:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="No fields to update",
        )

    # Hash PIN if being updated
    if "pin" in update_data:
        sec.pin_hash = hash_pin(update_data.pop("pin"))

    for field, value in update_data.items():
        setattr(sec, field, value)

    await db.flush()
    return sec


# ── Register Face ────────────────────────────────────────────────────────────
@router.post("/register-face", summary="Register face for 1:1 verification")
async def register_face(
    image: UploadFile = File(...),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    contents = await image.read()
    b64_str = base64.b64encode(contents).decode("utf-8")

    embedding = extract_face_embedding_from_b64(b64_str)
    if not embedding:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="No face detected or could not extract features. Ensure the photo is clear and well-lit.",
        )

    current_user.face_encoding = embedding
    db.add(current_user)
    await db.flush()

    return {"status": "success", "message": "Face registered successfully."}


# ── Verify Face (1:1 Match) ─────────────────────────────────────────────────
@router.post(
    "/verify-face",
    response_model=FaceVerifyResponse,
    summary="Verify a selfie against stored face data",
)
async def verify_face(
    image: UploadFile = File(...),
    current_user: User = Depends(get_current_user),
):
    # 1. Check that user has registered a face
    if not current_user.face_encoding:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="No face registered. Please register your face first.",
        )

    # 2. Extract embedding from the uploaded selfie
    contents = await image.read()
    b64_str = base64.b64encode(contents).decode("utf-8")
    live_embedding = extract_face_embedding_from_b64(b64_str)

    if not live_embedding:
        return FaceVerifyResponse(
            verified=False,
            message="No face detected in the image. Please ensure proper lighting and face visibility.",
        )

    # 3. Compare against stored embedding
    is_match = verify_face_match(live_embedding, current_user.face_encoding)

    if is_match:
        return FaceVerifyResponse(
            verified=True,
            message="Face verification successful. Identity confirmed.",
        )
    else:
        return FaceVerifyResponse(
            verified=False,
            message="Face does not match registered identity.",
        )


# ── Face Status ──────────────────────────────────────────────────────────────
@router.get(
    "/face-status",
    response_model=FaceStatusResponse,
    summary="Check face registration status",
)
async def face_status(
    current_user: User = Depends(get_current_user),
):
    return FaceStatusResponse(
        is_registered=bool(current_user.face_encoding),
        user_id=current_user.id,
    )
