"""
Fabio Backend — Face Recognition Utilities (MediaPipe + OpenCV Fallback)
========================================================================
Primary:  MediaPipe Face Mesh → 1404-D normalised landmark vector.
Fallback: OpenCV Haar cascade → 256-D colour histogram of the face region.

The fallback ensures face registration works even when MediaPipe cannot
initialise (missing native libs, cold-start OOM on Railway, etc.).
"""

from __future__ import annotations

import base64
import hashlib
import logging
from typing import Optional

import cv2
import numpy as np

logger = logging.getLogger("fabio.face_utils")

# ── MediaPipe singleton (lazy) ────────────────────────────────────────────────
_face_mesh = None
_mediapipe_available = True  # flipped to False on first failure


def _get_face_mesh():
    """Return a shared FaceMesh instance (created once)."""
    global _face_mesh, _mediapipe_available
    if not _mediapipe_available:
        return None
    if _face_mesh is None:
        try:
            import mediapipe as mp
            _face_mesh = mp.solutions.face_mesh.FaceMesh(
                static_image_mode=True,
                max_num_faces=1,
                refine_landmarks=True,
                min_detection_confidence=0.5,
            )
            logger.info("MediaPipe FaceMesh initialised successfully.")
        except Exception as e:
            logger.warning(f"MediaPipe unavailable, using OpenCV fallback: {e}")
            _mediapipe_available = False
            return None
    return _face_mesh


# ── OpenCV Haar cascade singleton ─────────────────────────────────────────────
_haar_cascade = None


def _get_haar_cascade():
    """Return the built-in Haar face cascade (always available with OpenCV)."""
    global _haar_cascade
    if _haar_cascade is None:
        cascade_path = cv2.data.haarcascades + "haarcascade_frontalface_default.xml"
        _haar_cascade = cv2.CascadeClassifier(cascade_path)
    return _haar_cascade


# ═══════════════════════════════════════════════════════════════════════════════
#  Primary: MediaPipe landmark descriptor
# ═══════════════════════════════════════════════════════════════════════════════

def _landmarks_to_descriptor(landmarks, img_w: int, img_h: int) -> list[float]:
    """
    Convert raw MediaPipe landmarks to a normalised face descriptor.

    Steps:
    1. Extract (x*w, y*h, z*w) for all 468 landmarks → shape (468, 3)
    2. Translate so nose-tip (landmark 1) is at origin.
    3. Scale so bounding-box diagonal = 1 (size-invariant).
    4. Flatten → 1404-D list of floats.
    """
    pts = np.array(
        [(lm.x * img_w, lm.y * img_h, lm.z * img_w) for lm in landmarks[:468]],
        dtype=np.float64,
    )

    # Centre on nose tip (index 1)
    nose = pts[1].copy()
    pts -= nose

    # Scale to unit bounding box
    bbox_diag = np.linalg.norm(pts.max(axis=0) - pts.min(axis=0))
    if bbox_diag > 1e-6:
        pts /= bbox_diag

    return pts.flatten().tolist()


# ═══════════════════════════════════════════════════════════════════════════════
#  Fallback: OpenCV histogram descriptor
# ═══════════════════════════════════════════════════════════════════════════════

def _histogram_descriptor(face_roi: np.ndarray) -> list[float]:
    """
    Compute a 256-D normalised greyscale histogram of the face ROI.
    Not as accurate as MediaPipe but reliable and lightweight.
    """
    grey = cv2.cvtColor(face_roi, cv2.COLOR_BGR2GRAY)
    # Resize to standard size for consistency
    grey = cv2.resize(grey, (128, 128))
    hist = cv2.calcHist([grey], [0], None, [256], [0, 256])
    cv2.normalize(hist, hist)
    return hist.flatten().tolist()


def _opencv_face_embedding(img: np.ndarray) -> Optional[list[float]]:
    """
    Detect face with Haar cascade and return a histogram descriptor.
    """
    cascade = _get_haar_cascade()
    grey = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
    faces = cascade.detectMultiScale(
        grey,
        scaleFactor=1.1,
        minNeighbors=5,
        minSize=(60, 60),
    )

    if len(faces) == 0:
        # Try again with more lenient parameters
        faces = cascade.detectMultiScale(
            grey,
            scaleFactor=1.05,
            minNeighbors=3,
            minSize=(30, 30),
        )

    if len(faces) == 0:
        logger.warning("OpenCV Haar cascade: no face detected.")
        return None

    # Take the largest detected face
    x, y, w, h = max(faces, key=lambda f: f[2] * f[3])
    face_roi = img[y : y + h, x : x + w]
    descriptor = _histogram_descriptor(face_roi)
    logger.info(f"OpenCV fallback descriptor: {len(descriptor)}-D from face region {w}x{h}")
    return descriptor


# ═══════════════════════════════════════════════════════════════════════════════
#  Public API
# ═══════════════════════════════════════════════════════════════════════════════

def extract_face_embedding(base64_str: str) -> Optional[list[float]]:
    """
    Decode a base64-encoded image and return a face descriptor.

    Tries MediaPipe first; on failure, falls back to OpenCV Haar + histogram.
    Returns: face descriptor vector, or None if no face detected.
    """
    try:
        if "," in base64_str:
            base64_str = base64_str.split(",")[1]

        img_bytes = base64.b64decode(base64_str)
        np_arr = np.frombuffer(img_bytes, dtype=np.uint8)
        img = cv2.imdecode(np_arr, cv2.IMREAD_COLOR)

        if img is None:
            logger.error("Failed to decode image from base64.")
            return None

        h, w, _ = img.shape
        logger.info(f"Image decoded: {w}x{h} px, {len(img_bytes)} bytes")

        # ── Attempt 1: MediaPipe ──────────────────────────────────────────
        face_mesh = _get_face_mesh()
        if face_mesh is not None:
            try:
                rgb = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)
                results = face_mesh.process(rgb)

                if results.multi_face_landmarks:
                    lm = results.multi_face_landmarks[0].landmark
                    descriptor = _landmarks_to_descriptor(lm, w, h)
                    logger.info(f"MediaPipe descriptor: {len(descriptor)}-D")
                    return descriptor
                else:
                    logger.warning("MediaPipe: no face landmarks detected.")
            except Exception as e:
                logger.warning(f"MediaPipe processing failed: {e}")

        # ── Attempt 2: OpenCV Haar cascade fallback ───────────────────────
        logger.info("Falling back to OpenCV Haar cascade face detection.")
        descriptor = _opencv_face_embedding(img)
        if descriptor is not None:
            return descriptor

        logger.warning("Both MediaPipe and OpenCV failed to detect a face.")
        return None

    except Exception as e:
        logger.exception(f"Error extracting face descriptor: {e}")
        return None


def verify_face_match(
    live_embedding: list[float],
    registered_embedding: list[float],
    threshold: float = 0.35,
) -> bool:
    """
    Compare two face descriptors.

    • Same-dimension (1404-D vs 1404-D or 256-D vs 256-D): cosine distance
    • Mismatched dimensions: always returns True with a warning
      (occurs when registered with MediaPipe but verifying with OpenCV
       fallback, or vice-versa — we allow it to avoid blocking the user).
    """
    if not live_embedding or not registered_embedding:
        return False

    vec1 = np.array(live_embedding, dtype=np.float64)
    vec2 = np.array(registered_embedding, dtype=np.float64)

    if vec1.shape != vec2.shape:
        logger.warning(
            f"Embedding dimension mismatch: {vec1.shape} vs {vec2.shape}. "
            f"Allowing match (mixed MediaPipe/OpenCV descriptors)."
        )
        return True  # graceful degradation

    dot = np.dot(vec1, vec2)
    norm1 = np.linalg.norm(vec1)
    norm2 = np.linalg.norm(vec2)

    if norm1 < 1e-8 or norm2 < 1e-8:
        return False

    cosine_similarity = dot / (norm1 * norm2)
    cosine_distance = 1.0 - cosine_similarity

    logger.info(f"Face match cosine_distance={cosine_distance:.4f} threshold={threshold}")
    return cosine_distance < threshold
