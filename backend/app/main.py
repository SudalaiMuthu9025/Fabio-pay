"""
Fabio Backend — FastAPI Application Entrypoint
================================================
Wires up REST routers, WebSocket liveness endpoint, CORS, lifespan,
health-check, and serves web portals as static files.
"""

from __future__ import annotations

import base64
import json
import os
from contextlib import asynccontextmanager
from pathlib import Path

import cv2
import numpy as np
from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, HTMLResponse
from fastapi.staticfiles import StaticFiles

from app.challenge import ChallengeEngine, ChallengeStatus
from app.config import settings
from app.database import init_db, get_db
from sqlalchemy.ext.asyncio import AsyncSession
from fastapi import Depends, Query
from datetime import datetime, timezone
from app.auth import get_user_from_token
from app.face_recognition import extract_face_embedding_from_b64, verify_face_match
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
from app.routers import admin as admin_router
from app.routers import google_auth

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
    import sys
    import os
    # Ensure root folder is in sys.path so seed_admin can be discovered safely
    root_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    if root_dir not in sys.path:
        sys.path.append(root_dir)

    await init_db()
    
    try:
        from seed_admin import seed_admin
        await seed_admin()
        print("Production Admin Seeding Completed.")
    except Exception as e:
        print(f"Admin Seeding bypassed/failed: {e}")

    yield


# ── App Instance ──────────────────────────────────────────────────────────────
app = FastAPI(
    title=settings.APP_NAME,
    description=(
        "FinTech API with Dynamic Anti-Spoofing Biometric System "
        "using Randomized Challenge-Response Sequences. "
        "Secured with HMAC-SHA256 session tokens and Google OAuth 2.0."
    ),
    version="1.0.0",
    lifespan=lifespan,
)

# ── CORS ──────────────────────────────────────────────────────────────────────
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.ALLOWED_ORIGINS.split(","),
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ── REST Routers ──────────────────────────────────────────────────────────────
app.include_router(auth.router)
app.include_router(google_auth.router)
app.include_router(users.router)
app.include_router(accounts.router)
app.include_router(security.router)
app.include_router(transactions.router)
app.include_router(admin_router.router)

# ── Web Portals (Static Files) ───────────────────────────────────────────────
# Determine the web directory path
BACKEND_DIR = Path(__file__).resolve().parent.parent
WEB_DIR = BACKEND_DIR.parent / "web"


def _mount_portal(path: str, folder: str):
    """Mount a web portal's static files if the directory exists."""
    portal_dir = WEB_DIR / folder
    if portal_dir.exists():
        app.mount(
            f"/{path}/assets",
            StaticFiles(directory=str(portal_dir / "assets")),
            name=f"{folder}_assets",
        )


# Mount static asset directories if they exist
for _path, _folder in [("admin", "admin"), ("vice", "vice"), ("portal", "user")]:
    try:
        _mount_portal(_path, _folder)
    except Exception:
        pass  # Static files not built yet


# ── Web Portal HTML Entry Points ─────────────────────────────────────────────
@app.get("/admin/{path:path}", include_in_schema=False)
async def admin_portal(path: str = ""):
    html_file = WEB_DIR / "admin" / "index.html"
    if html_file.exists():
        return FileResponse(str(html_file), media_type="text/html")
    return HTMLResponse("<h1>Admin portal not built yet</h1>", status_code=404)


@app.get("/vice/{path:path}", include_in_schema=False)
async def vice_portal(path: str = ""):
    html_file = WEB_DIR / "vice" / "index.html"
    if html_file.exists():
        return FileResponse(str(html_file), media_type="text/html")
    return HTMLResponse("<h1>Vice Admin portal not built yet</h1>", status_code=404)


@app.get("/portal/{path:path}", include_in_schema=False)
async def user_portal(path: str = ""):
    html_file = WEB_DIR / "user" / "index.html"
    if html_file.exists():
        return FileResponse(str(html_file), media_type="text/html")
    return HTMLResponse("<h1>User portal not built yet</h1>", status_code=404)


# ── Health Check ──────────────────────────────────────────────────────────────
@app.get("/", tags=["System"])
async def root():
    return {
        "status": "healthy",
        "app": settings.APP_NAME,
        "version": "1.0.0",
        "portals": {
            "admin": "/admin/",
            "vice_admin": "/vice/",
            "user": "/portal/",
            "api_docs": "/docs",
        },
    }


@app.get("/api/health", tags=["System"])
async def health():
    return {"status": "healthy", "app": settings.APP_NAME}


# ═══════════════════════════════════════════════════════════════════════════════
#  WebSocket — Active Liveness Verification
# ═══════════════════════════════════════════════════════════════════════════════

@app.websocket("/ws/liveness")
async def websocket_liveness(
    ws: WebSocket,
    token: str = Query(...),
    db: AsyncSession = Depends(get_db)
):
    await ws.accept()

    # 1. Authenticate WebSocket 
    user = await get_user_from_token(token, db)
    if not user:
        await ws.send_json({"type": "error", "message": "Authentication failed"})
        await ws.close()
        return
        
    engine = ChallengeEngine()
    progress = engine.start()
    
    # 2. Setup Verification Flags
    is_identity_verified = False if user.face_encoding else True # If no face enrolled, skip identity (fail open for simple usage, or fail closed based on config)
    # Actually, we should enforce identity verification if enrolled:
    enrolled_embedding = user.face_encoding

    await ws.send_json({
        "type": "challenge",
        "sequence": engine.sequence,
        "timeout": engine.timeout,
        "current_action": engine.current_action,
        "identity_verified": is_identity_verified,
    })

    face_mesh = _get_face_mesh()

    try:
        while engine.status.value == "in_progress":
            data = await ws.receive_text()
            payload = json.loads(data)

            frame_b64 = payload.get("frame", "")
            frame_bytes = base64.b64decode(frame_b64)
            np_arr = np.frombuffer(frame_bytes, dtype=np.uint8)
            frame = cv2.imdecode(np_arr, cv2.IMREAD_COLOR)

            if frame is None:
                await ws.send_json({"type": "error", "message": "Invalid frame"})
                continue

            h, w, _ = frame.shape
            rgb_frame = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)

            results = face_mesh.process(rgb_frame)

            if not results.multi_face_landmarks:
                await ws.send_json({
                    "type": "feedback",
                    "detected": None,
                    "message": "No face detected — move closer to camera",
                    "progress": engine.progress,
                })
                continue
                
            # Identity Verification (1:1 Match) block
            if enrolled_embedding and not is_identity_verified:
                live_embedding = extract_face_embedding_from_b64(frame_b64)
                if live_embedding is None:
                    await ws.send_json({"type": "feedback", "message": "Analyzing face..."})
                    continue
                
                is_match = verify_face_match(live_embedding, enrolled_embedding)
                if is_match:
                    is_identity_verified = True
                else:
                    await ws.send_json({"type": "error", "message": "Face does not match registered owner."})
                    engine.status = ChallengeStatus.FAILED
                    break

            landmarks = results.multi_face_landmarks[0]
            lm = landmarks.landmark

            right_eye = [(lm[i].x * w, lm[i].y * h) for i in RIGHT_EYE_IDX]
            left_eye = [(lm[i].x * w, lm[i].y * h) for i in LEFT_EYE_IDX]
            mouth = [(lm[i].x * w, lm[i].y * h) for i in MOUTH_IDX]
            head_pts = [(lm[idx].x, lm[idx].y) for idx in HEAD_POSE_IDX.values()]

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

            if detected_action and detected_action == engine.current_action:
                engine.submit_action(detected_action)

            await ws.send_json({
                "type": "feedback",
                "detected": detected_action,
                "ear": round(ear_val, 3),
                "mar": round(mar_val, 3),
                "head_direction": head_data["direction"],
                "progress": engine.progress,
                "identity_verified": is_identity_verified,
            })

            if engine.is_timed_out:
                engine.status = ChallengeStatus.TIMED_OUT
                break

    except WebSocketDisconnect:
        engine.status = ChallengeStatus.FAILED

    # ── Persist liveness result to DB ─────────────────────────────────────
    if engine.status == ChallengeStatus.PASSED:
        try:
            user.liveness_verified = True
            user.last_liveness_at = datetime.now(timezone.utc)
            user.liveness_count = (user.liveness_count or 0) + 1
            await db.flush()
            await db.commit()
        except Exception:
            pass  # Non-blocking — don't fail the WS response

    try:
        await ws.send_json({
            "type": "result",
            "status": engine.status.value,
            "sequence": engine.sequence,
            "results": engine.results,
        })
    except Exception:
        pass

    try:
        await ws.close()
    except Exception:
        pass
