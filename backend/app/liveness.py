"""
Fabio Backend — Active Liveness Biometric Functions
=====================================================
Core computer-vision math for anti-spoofing challenge verification.

Functions
---------
* `calculate_euclidean_distance`  — 2D/3D point distance
* `calculate_ear`                 — Eye Aspect Ratio (blink detection)
* `calculate_mar`                 — Mouth Aspect Ratio (smile detection)
* `estimate_head_pose`            — Pitch / Yaw / Roll via cv2.solvePnP

MediaPipe Landmark Indices Used
-------------------------------
* Right eye : [33, 160, 158, 133, 153, 144]
* Left  eye : [362, 385, 387, 263, 373, 380]
* Mouth     : [61, 291, 39, 181, 0, 17, 269, 405]
* Head pose : nose=1, chin=152, left_eye_corner=263,
              right_eye_corner=33, left_mouth=287, right_mouth=57
"""

from __future__ import annotations

import math
from typing import Sequence

import numpy as np

# ═══════════════════════════════════════════════════════════════════════════════
#  Landmark index constants (MediaPipe Face Mesh — 468 landmarks)
# ═══════════════════════════════════════════════════════════════════════════════

# Eye landmarks (6 points each for EAR)
RIGHT_EYE_IDX = [33, 160, 158, 133, 153, 144]
LEFT_EYE_IDX = [362, 385, 387, 263, 373, 380]

# Mouth landmarks (8 points for MAR — 4 vertical + 2 horizontal anchors)
MOUTH_IDX = [61, 291, 39, 181, 0, 17, 269, 405]

# Head pose landmarks (6 key points)
HEAD_POSE_IDX = {
    "nose_tip": 1,
    "chin": 152,
    "left_eye_corner": 263,
    "right_eye_corner": 33,
    "left_mouth_corner": 287,
    "right_mouth_corner": 57,
}

# ── Thresholds (defaults from config, but also available standalone) ──────────
EAR_THRESHOLD = 0.2   # Below this = blink detected
MAR_THRESHOLD = 0.5   # Above this = mouth open (smile / yawn)


# ═══════════════════════════════════════════════════════════════════════════════
#  Core Math
# ═══════════════════════════════════════════════════════════════════════════════

def calculate_euclidean_distance(
    point1: Sequence[float],
    point2: Sequence[float],
) -> float:
    """
    Euclidean distance between two 2D or 3D points.

    Parameters
    ----------
    point1, point2 : tuple/list of (x, y) or (x, y, z)

    Returns
    -------
    float — distance ≥ 0
    """
    return math.sqrt(sum((a - b) ** 2 for a, b in zip(point1, point2)))


# ═══════════════════════════════════════════════════════════════════════════════
#  Eye Aspect Ratio (EAR) — Blink Detection
# ═══════════════════════════════════════════════════════════════════════════════

def calculate_ear(eye_points: list[tuple[float, float]]) -> float:
    """
    Compute the Eye Aspect Ratio for a single eye.

    Expected order (6 points — MediaPipe convention):
        P0 = lateral corner (outer)
        P1 = upper-lid-1
        P2 = upper-lid-2
        P3 = medial corner (inner)
        P4 = lower-lid-1
        P5 = lower-lid-2

    Formula
    -------
        EAR = (‖P1-P5‖ + ‖P2-P4‖) / (2 · ‖P0-P3‖)

    Returns
    -------
    float — ratio (low value ≈ eye closed)
    """
    if len(eye_points) != 6:
        raise ValueError(f"Expected 6 eye landmarks, got {len(eye_points)}")

    # Vertical distances (upper-lid to lower-lid)
    v1 = calculate_euclidean_distance(eye_points[1], eye_points[5])
    v2 = calculate_euclidean_distance(eye_points[2], eye_points[4])

    # Horizontal distance (corner to corner)
    h = calculate_euclidean_distance(eye_points[0], eye_points[3])

    if h == 0:
        return 0.0

    return (v1 + v2) / (2.0 * h)


def detect_blink(
    left_eye: list[tuple[float, float]],
    right_eye: list[tuple[float, float]],
    threshold: float = EAR_THRESHOLD,
) -> tuple[bool, float]:
    """
    Detect a blink by averaging the EAR of both eyes.

    Returns
    -------
    (is_blinking, avg_ear)
    """
    ear_left = calculate_ear(left_eye)
    ear_right = calculate_ear(right_eye)
    avg_ear = (ear_left + ear_right) / 2.0
    return avg_ear < threshold, avg_ear


# ═══════════════════════════════════════════════════════════════════════════════
#  Mouth Aspect Ratio (MAR) — Smile / Yawn Detection
# ═══════════════════════════════════════════════════════════════════════════════

def calculate_mar(mouth_points: list[tuple[float, float]]) -> float:
    """
    Compute the Mouth Aspect Ratio.

    Expected order (8 points):
        P0 = left corner        P1 = right corner
        P2 = upper-lip-left     P3 = lower-lip-left
        P4 = upper-lip-center   P5 = lower-lip-center
        P6 = upper-lip-right    P7 = lower-lip-right

    Formula
    -------
        MAR = (‖P2-P3‖ + ‖P4-P5‖ + ‖P6-P7‖) / (2 · ‖P0-P1‖)

    Returns
    -------
    float — ratio (high value ≈ mouth open)
    """
    if len(mouth_points) != 8:
        raise ValueError(f"Expected 8 mouth landmarks, got {len(mouth_points)}")

    # Three vertical distances across upper/lower lip
    v1 = calculate_euclidean_distance(mouth_points[2], mouth_points[3])
    v2 = calculate_euclidean_distance(mouth_points[4], mouth_points[5])
    v3 = calculate_euclidean_distance(mouth_points[6], mouth_points[7])

    # Horizontal distance (corner to corner)
    h = calculate_euclidean_distance(mouth_points[0], mouth_points[1])

    if h == 0:
        return 0.0

    return (v1 + v2 + v3) / (2.0 * h)


def detect_smile(
    mouth: list[tuple[float, float]],
    threshold: float = MAR_THRESHOLD,
) -> tuple[bool, float]:
    """
    Detect mouth opening (smile / yawn).

    Returns
    -------
    (is_mouth_open, mar_value)
    """
    mar = calculate_mar(mouth)
    return mar > threshold, mar


# ═══════════════════════════════════════════════════════════════════════════════
#  Smirk Detection — Asymmetric Mouth Corner Analysis
# ═══════════════════════════════════════════════════════════════════════════════

# Additional landmark indices for smirk detection
# Left mouth corner = 61, Right mouth corner = 291
# Upper lip center = 13, Lower lip center = 14
SMIRK_LEFT_CORNER = 61
SMIRK_RIGHT_CORNER = 291
SMIRK_UPPER_LIP = 13
SMIRK_LOWER_LIP = 14
SMIRK_THRESHOLD = 0.015  # Minimum asymmetry ratio for smirk detection


def detect_smirk(
    landmarks,
    img_w: int,
    img_h: int,
    threshold: float = SMIRK_THRESHOLD,
) -> tuple[bool, float]:
    """
    Detect a smirk (asymmetric one-sided smile).

    A smirk occurs when one mouth corner is raised significantly higher
    than the other relative to the mouth width.

    Parameters
    ----------
    landmarks : MediaPipe landmark list
    img_w, img_h : image dimensions
    threshold : minimum asymmetry ratio

    Returns
    -------
    (is_smirking, asymmetry_ratio)
    """
    try:
        lm = landmarks

        left_corner_y = lm[SMIRK_LEFT_CORNER].y * img_h
        right_corner_y = lm[SMIRK_RIGHT_CORNER].y * img_h
        left_corner_x = lm[SMIRK_LEFT_CORNER].x * img_w
        right_corner_x = lm[SMIRK_RIGHT_CORNER].x * img_w

        # Mouth width for normalisation
        mouth_width = calculate_euclidean_distance(
            (left_corner_x, left_corner_y),
            (right_corner_x, right_corner_y),
        )

        if mouth_width < 1e-6:
            return False, 0.0

        # Height difference between corners (positive = left corner higher)
        corner_diff = abs(left_corner_y - right_corner_y)
        asymmetry = corner_diff / mouth_width

        return asymmetry > threshold, asymmetry

    except (IndexError, AttributeError):
        return False, 0.0


# ═══════════════════════════════════════════════════════════════════════════════
#  Head Pose Estimation — Left / Right / Center
# ═══════════════════════════════════════════════════════════════════════════════

# 3D model reference points (generic face model in mm)
_MODEL_POINTS = np.array(
    [
        (0.0, 0.0, 0.0),          # Nose tip
        (0.0, -330.0, -65.0),     # Chin
        (-225.0, 170.0, -135.0),  # Left eye left corner
        (225.0, 170.0, -135.0),   # Right eye right corner
        (-150.0, -150.0, -125.0), # Left mouth corner
        (150.0, -150.0, -125.0),  # Right mouth corner
    ],
    dtype=np.float64,
)


def estimate_head_pose(
    face_landmarks: list[tuple[float, float]],
    frame_width: int,
    frame_height: int,
) -> dict[str, float | str]:
    """
    Estimate head Pitch, Yaw, Roll using cv2.solvePnP.

    Parameters
    ----------
    face_landmarks : 6 key points [(x, y), ...] in normalised [0..1] coords
    frame_width, frame_height : image dimensions in pixels

    Returns
    -------
    {"pitch": float, "yaw": float, "roll": float, "direction": "Left"|"Right"|"Center"}
    """
    try:
        import cv2
    except ImportError:
        return {"pitch": 0.0, "yaw": 0.0, "roll": 0.0, "direction": "Center"}

    if len(face_landmarks) != 6:
        raise ValueError(f"Expected 6 head-pose landmarks, got {len(face_landmarks)}")

    # Convert normalised coords → pixel coords
    image_points = np.array(
        [(x * frame_width, y * frame_height) for x, y in face_landmarks],
        dtype=np.float64,
    )

    # Camera internals (approximation)
    focal_length = frame_width
    center = (frame_width / 2.0, frame_height / 2.0)
    camera_matrix = np.array(
        [
            [focal_length, 0, center[0]],
            [0, focal_length, center[1]],
            [0, 0, 1],
        ],
        dtype=np.float64,
    )
    dist_coeffs = np.zeros((4, 1), dtype=np.float64)

    # Solve PnP
    success, rotation_vec, translation_vec = cv2.solvePnP(
        _MODEL_POINTS,
        image_points,
        camera_matrix,
        dist_coeffs,
        flags=cv2.SOLVEPNP_ITERATIVE,
    )

    if not success:
        return {"pitch": 0.0, "yaw": 0.0, "roll": 0.0, "direction": "Center"}

    # Convert rotation vector to Euler angles (degrees)
    rotation_mat, _ = cv2.Rodrigues(rotation_vec)
    pose_mat = np.hstack((rotation_mat, translation_vec))
    _, _, _, _, _, _, euler_angles = cv2.decomposeProjectionMatrix(
        np.vstack((pose_mat, [0, 0, 0, 1]))[:3]
    )

    pitch = float(euler_angles[0, 0])
    yaw = float(euler_angles[1, 0])
    roll = float(euler_angles[2, 0])

    # Determine direction from yaw
    if yaw < -15:
        direction = "Right"   # Face turned to their right → camera sees left
    elif yaw > 15:
        direction = "Left"
    else:
        direction = "Center"

    return {"pitch": pitch, "yaw": yaw, "roll": roll, "direction": direction}


# ═══════════════════════════════════════════════════════════════════════════════
#  Landmark Extraction Helper
# ═══════════════════════════════════════════════════════════════════════════════

def extract_landmarks_from_mediapipe(face_landmarks) -> dict:
    """
    Given a MediaPipe `face_landmarks` result, extract the specific landmark
    groups needed for EAR, MAR, and head pose.

    Parameters
    ----------
    face_landmarks : mediapipe.framework.formats.landmark_pb2.NormalizedLandmarkList

    Returns
    -------
    dict with keys: "right_eye", "left_eye", "mouth", "head_pose"
    """
    lm = face_landmarks.landmark

    right_eye = [(lm[i].x, lm[i].y) for i in RIGHT_EYE_IDX]
    left_eye = [(lm[i].x, lm[i].y) for i in LEFT_EYE_IDX]
    mouth = [(lm[i].x, lm[i].y) for i in MOUTH_IDX]
    head_pose = [(lm[idx].x, lm[idx].y) for idx in HEAD_POSE_IDX.values()]

    return {
        "right_eye": right_eye,
        "left_eye": left_eye,
        "mouth": mouth,
        "head_pose": head_pose,
    }
