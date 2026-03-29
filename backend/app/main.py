"""
Fabio Backend — FastAPI Application Entrypoint
================================================
Wires up REST routers, WebSocket liveness endpoint, CORS, lifespan, health-check.
"""

from __future__ import annotations

import base64
import json
from contextlib import asynccontextmanager

import cv2
import numpy as np
from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware

from app.challenge import ChallengeEngine
from app.config import settings
from app.database import init_db
from app.liveness import (
    HEAD_POSE_IDX,
    LEFT_EYE_IDX,
    MOUTH_IDX,
    RIGHT_EYE_IDX,
    detect_blink,
    detect_smile,
    estimate_head_pose,
)
from app.routers import accounts, auth, security, transactions, users

# Lazy-load MediaPipe (heavy import)
_face_mesh = None


def _get_face_mesh():
    global _face_mesh
    if _face_mesh is None:
        import mediapipe as mp
        _face_mesh = mp.solutions.face_mesh.FaceMesh(
            static_image_mode=False,
            max_num_faces=1,
            refine_landmarks=True,
            min_detection_confidence=0.5,
            min_tracking_confidence=0.5,
        )
    return _face_mesh


# ── Lifespan ──────────────────────────────────────────────────────────────────
@asynccontextmanager
async def lifespan(app: FastAPI):
    """Run once on startup: create DB tables if they don't exist."""
    await init_db()
    yield


# ── App Instance ──────────────────────────────────────────────────────────────
app = FastAPI(
    title=settings.APP_NAME,
    description=(
        "FinTech API with Dynamic Anti-Spoofing Biometric System "
        "using Randomized Challenge-Response Sequences."
    ),
    version="0.1.0",
    lifespan=lifespan,
)

# ── CORS (allow Flutter dev & production origins) ────────────────────────────
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # tighten in production
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ── REST Routers ──────────────────────────────────────────────────────────────
app.include_router(auth.router)
app.include_router(users.router)
app.include_router(accounts.router)
app.include_router(security.router)
app.include_router(transactions.router)


# ── Health Check ──────────────────────────────────────────────────────────────
@app.get("/", tags=["System"])
async def root():
    return {"status": "healthy", "app": settings.APP_NAME, "version": "0.1.0"}


@app.get("/api/health", tags=["System"])
async def health():
    return {"status": "healthy", "app": settings.APP_NAME}


# ═══════════════════════════════════════════════════════════════════════════════
#  WebSocket — Active Liveness Verification
# ═══════════════════════════════════════════════════════════════════════════════
#
#  Protocol (client ↔ server):
#
#  1. Client connects to  ws://<host>/ws/liveness
#  2. Server sends:       {"type": "challenge", "sequence": [...], "timeout": 15}
#  3. Client sends:       base64-encoded JPEG frames (720p/1080p)
#  4. Server responds:    {"type": "feedback", "detected": "Blink", ...}
#  5. On completion:      {"type": "result", "status": "passed" | "failed"}
#
# ═══════════════════════════════════════════════════════════════════════════════

@app.websocket("/ws/liveness")
async def websocket_liveness(ws: WebSocket):
    await ws.accept()

    # 1. Generate challenge
    engine = ChallengeEngine()
    progress = engine.start()

    # 2. Send challenge to client
    await ws.send_json({
        "type": "challenge",
        "sequence": engine.sequence,
        "timeout": engine.timeout,
        "current_action": engine.current_action,
    })

    face_mesh = _get_face_mesh()

    try:
        while engine.status.value == "in_progress":
            # 3. Receive a frame from the client
            data = await ws.receive_text()
            payload = json.loads(data)

            # Decode base64 JPEG → OpenCV frame
            frame_b64 = payload.get("frame", "")
            frame_bytes = base64.b64decode(frame_b64)
            np_arr = np.frombuffer(frame_bytes, dtype=np.uint8)
            frame = cv2.imdecode(np_arr, cv2.IMREAD_COLOR)

            if frame is None:
                await ws.send_json({"type": "error", "message": "Invalid frame"})
                continue

            h, w, _ = frame.shape
            rgb_frame = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)

            # 4. Process with MediaPipe
            results = face_mesh.process(rgb_frame)

            if not results.multi_face_landmarks:
                await ws.send_json({
                    "type": "feedback",
                    "detected": None,
                    "message": "No face detected — move closer to camera",
                    "progress": engine.progress,
                })
                continue

            landmarks = results.multi_face_landmarks[0]
            lm = landmarks.landmark

            # Extract landmark groups
            right_eye = [(lm[i].x * w, lm[i].y * h) for i in RIGHT_EYE_IDX]
            left_eye = [(lm[i].x * w, lm[i].y * h) for i in LEFT_EYE_IDX]
            mouth = [(lm[i].x * w, lm[i].y * h) for i in MOUTH_IDX]
            head_pts = [(lm[idx].x, lm[idx].y) for idx in HEAD_POSE_IDX.values()]

            # 5. Detect what the user is doing
            is_blinking, ear_val = detect_blink(left_eye, right_eye)
            is_smiling, mar_val = detect_smile(mouth)
            head_data = estimate_head_pose(head_pts, w, h)

            detected_action = None
            if is_blinking:
                detected_action = "Blink"
            elif is_smiling:
                detected_action = "Smile"
            elif head_data["direction"] == "Left":
                detected_action = "Left"
            elif head_data["direction"] == "Right":
                detected_action = "Right"

            # 6. Submit to challenge engine (temporal logic check)
            if detected_action and detected_action == engine.current_action:
                engine.submit_action(detected_action)

            # 7. Send feedback
            await ws.send_json({
                "type": "feedback",
                "detected": detected_action,
                "ear": round(ear_val, 3),
                "mar": round(mar_val, 3),
                "head_direction": head_data["direction"],
                "progress": engine.progress,
            })

            # Check timeout
            if engine.is_timed_out:
                engine.status = engine.status.__class__("timed_out")
                break

    except WebSocketDisconnect:
        engine.status = engine.status.__class__("failed")

    # 8. Send final result
    try:
        await ws.send_json({
            "type": "result",
            "status": engine.status.value,
            "sequence": engine.sequence,
            "results": engine.results,
        })
    except Exception:
        pass  # Client may have already disconnected

    try:
        await ws.close()
    except Exception:
        pass
