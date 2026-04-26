"""
Fabio Backend — WebSocket Liveness Router
==========================================
GET /ws/liveness?token=<jwt>

Streams base64 JPEG frames from the Flutter front-camera.
Runs a randomised 3-action Simon-Says challenge using MediaPipe
Face Mesh (EAR / MAR / solvePnP).  On PASS the caller receives
{"type":"result","status":"passed"} and the WS closes cleanly.
"""

from __future__ import annotations

import asyncio
import base64
import json
import logging
import random
import time
from typing import Any

import cv2
import numpy as np
from fastapi import APIRouter, WebSocket, WebSocketDisconnect, status
from jose import JWTError
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth import decode_access_token
from app.config import settings
from app.database import async_session_factory
from app.models import User

logger = logging.getLogger("fabio.ws_liveness")
router = APIRouter()

# ── Challenge actions ────────────────────────────────────────────────────────
ACTIONS = ["Blink", "Smile", "Smirk", "Turn Left", "Turn Right"]

# MediaPipe landmark indices
LEFT_EYE  = [362, 385, 387, 263, 373, 380]
RIGHT_EYE = [33,  160, 158, 133, 153, 144]
LIPS_V    = [13, 14]
LIPS_H    = [78, 308]

# 3-D reference model points for solvePnP head-pose
MODEL_POINTS = np.array([
    (0.0,    0.0,    0.0),
    (0.0,   -330.0, -65.0),
    (-225.0, 170.0, -135.0),
    (225.0,  170.0, -135.0),
    (-150.0,-150.0, -125.0),
    (150.0, -150.0, -125.0),
], dtype=np.float64)
FACE_INDICES = [1, 152, 226, 446, 57, 287]


# ── Helpers ──────────────────────────────────────────────────────────────────

def _eye_aspect_ratio(landmarks: list, indices: list[int], w: int, h: int) -> float:
    pts = [(int(landmarks[i].x * w), int(landmarks[i].y * h)) for i in indices]
    A = np.linalg.norm(np.array(pts[1]) - np.array(pts[5]))
    B = np.linalg.norm(np.array(pts[2]) - np.array(pts[4]))
    C = np.linalg.norm(np.array(pts[0]) - np.array(pts[3]))
    return (A + B) / (2.0 * C) if C > 1e-6 else 0.0


def _mouth_aspect_ratio(landmarks: list, w: int, h: int) -> float:
    top    = landmarks[13]; bottom = landmarks[14]
    left   = landmarks[78]; right  = landmarks[308]
    V = np.linalg.norm(
        np.array([top.x * w, top.y * h]) - np.array([bottom.x * w, bottom.y * h])
    )
    H = np.linalg.norm(
        np.array([left.x * w, left.y * h]) - np.array([right.x * w, right.y * h])
    )
    return V / H if H > 1e-6 else 0.0


def _head_yaw(landmarks: list, w: int, h: int) -> float:
    img_pts = np.array(
        [(landmarks[i].x * w, landmarks[i].y * h) for i in FACE_INDICES],
        dtype=np.float64,
    )
    cam = np.array([[w, 0, w / 2], [0, w, h / 2], [0, 0, 1]], dtype=np.float64)
    dist = np.zeros((4, 1))
    ok, rvec, _ = cv2.solvePnP(MODEL_POINTS, img_pts, cam, dist)
    if not ok:
        return 0.0
    rmat, _ = cv2.Rodrigues(rvec)
    sy = (rmat[0, 0] ** 2 + rmat[1, 0] ** 2) ** 0.5
    yaw = np.degrees(np.arctan2(-rmat[2, 0], sy))
    return float(yaw)


def _detect_action(action: str, landmarks: list, w: int, h: int) -> bool:
    ear_t  = settings.EAR_THRESHOLD
    mar_t  = settings.MAR_THRESHOLD

    if action == "Blink":
        ear = (_eye_aspect_ratio(landmarks, LEFT_EYE, w, h)
               + _eye_aspect_ratio(landmarks, RIGHT_EYE, w, h)) / 2
        return ear < ear_t

    if action == "Smile":
        return _mouth_aspect_ratio(landmarks, w, h) > mar_t

    if action == "Smirk":
        mar = _mouth_aspect_ratio(landmarks, w, h)
        return 0.30 < mar < 0.50

    if action == "Turn Left":
        return _head_yaw(landmarks, w, h) > 20.0

    if action == "Turn Right":
        return _head_yaw(landmarks, w, h) < -20.0

    return False


def _decode_frame(b64: str):
    """Return (img_bgr, h, w) or None on failure."""
    try:
        if "," in b64:
            b64 = b64.split(",")[1]
        raw = base64.b64decode(b64)
        arr = np.frombuffer(raw, np.uint8)
        img = cv2.imdecode(arr, cv2.IMREAD_COLOR)
        if img is None:
            return None
        h, w = img.shape[:2]
        return img, h, w
    except Exception:
        return None


async def _get_user_from_token(token: str) -> User | None:
    try:
        payload = decode_access_token(token)
        user_id = payload.get("sub")
        if not user_id:
            return None
    except JWTError:
        return None

    async with async_session_factory() as db:
        result = await db.execute(select(User).where(User.id == user_id))
        return result.scalar_one_or_none()


# ── Lazy MediaPipe init ───────────────────────────────────────────────────────
_face_mesh = None


def _get_mesh():
    global _face_mesh
    if _face_mesh is None:
        import mediapipe as mp
        _face_mesh = mp.solutions.face_mesh.FaceMesh(
            static_image_mode=True,
            max_num_faces=1,
            refine_landmarks=True,
            min_detection_confidence=0.5,
        )
    return _face_mesh


# ── WebSocket handler ────────────────────────────────────────────────────────

@router.websocket("/ws/liveness")
async def liveness_ws(ws: WebSocket, token: str = ""):
    """
    Query param:  ?token=<JWT>
    Protocol:
      Server → {"type":"challenge","sequence":[…],"current_action":"Blink","timeout":15}
      Client → {"frame":"<base64 jpeg>"}
      Server → {"type":"feedback","progress":{…},"detected":"Blink"}
      Server → {"type":"result","status":"passed"|"failed"|"timed_out","message":"…"}
    """
    await ws.accept()

    user = await _get_user_from_token(token)
    if user is None:
        await ws.send_text(json.dumps({"type": "error", "message": "Unauthorised"}))
        await ws.close(code=status.WS_1008_POLICY_VIOLATION)
        return

    n = settings.CHALLENGE_COUNT
    sequence: list[str] = random.sample(ACTIONS, k=min(n, len(ACTIONS)))
    timeout   = settings.PANIC_TIMER_SECONDS
    results: list[bool] = []
    current   = 0
    passed    = False

    await ws.send_text(json.dumps({
        "type":           "challenge",
        "sequence":       sequence,
        "current_action": sequence[0],
        "timeout":        timeout,
    }))

    deadline = time.monotonic() + timeout

    try:
        while current < len(sequence):
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                await ws.send_text(json.dumps({
                    "type":    "result",
                    "status":  "timed_out",
                    "message": "Challenge timed out",
                }))
                await ws.close()
                return

            try:
                raw = await asyncio.wait_for(ws.receive_text(), timeout=min(remaining, 2.0))
            except asyncio.TimeoutError:
                continue

            try:
                msg: dict[str, Any] = json.loads(raw)
            except json.JSONDecodeError:
                continue

            b64 = msg.get("frame", "")
            if not b64:
                continue

            decoded = _decode_frame(b64)
            if decoded is None:
                continue

            img_bgr, h, w = decoded
            rgb = cv2.cvtColor(img_bgr, cv2.COLOR_BGR2RGB)

            mesh   = _get_mesh()
            result = mesh.process(rgb)

            if not result.multi_face_landmarks:
                continue

            lm      = result.multi_face_landmarks[0].landmark
            action  = sequence[current]
            detected = _detect_action(action, lm, w, h)

            await ws.send_text(json.dumps({
                "type":    "feedback",
                "detected": action if detected else None,
                "progress": {
                    "current_index":  current,
                    "current_action": action,
                    "results":        results,
                    "remaining_time": round(deadline - time.monotonic(), 1),
                },
            }))

            if detected:
                results.append(True)
                current += 1
                if current < len(sequence):
                    await ws.send_text(json.dumps({
                        "type":    "feedback",
                        "message": f"✓ {action} — now: {sequence[current]}",
                        "progress": {
                            "current_index":  current,
                            "current_action": sequence[current],
                            "results":        results,
                            "remaining_time": round(deadline - time.monotonic(), 1),
                        },
                    }))

        passed = all(results) and len(results) == len(sequence)
        await ws.send_text(json.dumps({
            "type":    "result",
            "status":  "passed" if passed else "failed",
            "message": "Liveness verified" if passed else "Challenge failed",
            "transaction_completed": False,
        }))

    except WebSocketDisconnect:
        logger.info("Client disconnected during liveness check")
    except Exception as exc:
        logger.exception(f"Liveness WS error: {exc}")
        try:
            await ws.send_text(json.dumps({"type": "error", "message": str(exc)}))
        except Exception:
            pass
    finally:
        try:
            await ws.close()
        except Exception:
            pass
