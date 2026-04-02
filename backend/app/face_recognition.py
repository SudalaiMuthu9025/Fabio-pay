"""
Fabio Backend — Face Recognition Utilities (MediaPipe)
========================================================
Uses MediaPipe Face Mesh to extract normalized 3D facial landmarks
as a face descriptor for 1:1 identity verification.

Approach
--------
1. MediaPipe Face Mesh extracts 468 3D landmarks from a face image.
2. Landmarks are centred (nose-tip origin) and scaled to unit bounding-box.
3. The normalised (x, y, z) triplets are flattened → 1404-D vector.
4. Cosine similarity between two vectors decides match/no-match.

This avoids heavy deep-learning libraries (DeepFace / TF-Keras / dlib)
and reuses the same MediaPipe already loaded for liveness detection.
"""

from __future__ import annotations

import base64
import logging
from typing import Optional

import cv2
import numpy as np

logger = logging.getLogger("fabio.face_recognition")

# Lazy-loaded singleton — heavy import
_face_mesh = None


def _get_face_mesh():
    """Return a shared FaceMesh instance (created once)."""
    global _face_mesh
    if _face_mesh is None:
        import mediapipe as mp
        _face_mesh = mp.solutions.face_mesh.FaceMesh(
            static_image_mode=True,       # single image, not video stream
            max_num_faces=1,
            refine_landmarks=True,         # 478 landmarks incl. iris
            min_detection_confidence=0.5,
        )
    return _face_mesh


# ═══════════════════════════════════════════════════════════════════════════════
#  Landmark Normalisation → Face Descriptor
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
#  Public API
# ═══════════════════════════════════════════════════════════════════════════════

def extract_face_embedding_from_b64(base64_str: str) -> Optional[list[float]]:
    """
    Decode a base64-encoded image and return a MediaPipe face descriptor.

    Returns
    -------
    list[float] | None
        1404-D normalised landmark vector, or None if no face detected.
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
        rgb = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)

        results = _get_face_mesh().process(rgb)

        if not results.multi_face_landmarks:
            logger.warning("No face detected in provided image.")
            return None

        lm = results.multi_face_landmarks[0].landmark
        return _landmarks_to_descriptor(lm, w, h)

    except Exception as e:
        logger.exception(f"Error extracting face descriptor: {e}")
        return None


def extract_face_embedding_from_bytes(raw_bytes: bytes) -> Optional[list[float]]:
    """
    Extract face descriptor from raw image bytes (no base64).
    Convenience wrapper for registration endpoint using UploadFile.
    """
    b64 = base64.b64encode(raw_bytes).decode("utf-8")
    return extract_face_embedding_from_b64(b64)


def verify_face_match(
    live_embedding: list[float],
    registered_embedding: list[float],
    threshold: float = 0.35,
) -> bool:
    """
    Compare two face descriptors using Cosine Distance.

    Parameters
    ----------
    live_embedding : list[float]
        Descriptor from the live camera frame.
    registered_embedding : list[float]
        Descriptor stored in the database.
    threshold : float
        Maximum cosine distance for a match (lower = stricter).
        Default 0.35 tuned for MediaPipe 468-landmark descriptors.

    Returns
    -------
    bool — True if the faces match (distance < threshold).
    """
    if not live_embedding or not registered_embedding:
        return False

    vec1 = np.array(live_embedding, dtype=np.float64)
    vec2 = np.array(registered_embedding, dtype=np.float64)

    if vec1.shape != vec2.shape:
        logger.warning(
            f"Embedding dimension mismatch: {vec1.shape} vs {vec2.shape}"
        )
        return False

    dot = np.dot(vec1, vec2)
    norm1 = np.linalg.norm(vec1)
    norm2 = np.linalg.norm(vec2)

    if norm1 < 1e-8 or norm2 < 1e-8:
        return False

    cosine_similarity = dot / (norm1 * norm2)
    cosine_distance = 1.0 - cosine_similarity

    logger.debug(f"Face match cosine_distance={cosine_distance:.4f} threshold={threshold}")
    return cosine_distance < threshold
