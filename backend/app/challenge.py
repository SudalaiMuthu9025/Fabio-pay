"""
Fabio Backend — "Simon Says" Challenge State Machine
======================================================
Generates a randomized sequence of actions, enforces temporal order,
and manages the panic timer for anti-spoofing verification.
"""

from __future__ import annotations

import asyncio
import random
import time
from enum import Enum
from typing import Optional

from app.config import settings


class ChallengeAction(str, Enum):
    """Supported liveness challenge actions."""
    BLINK = "Blink"
    SMILE = "Smile"
    LEFT = "Left"
    RIGHT = "Right"


class ChallengeStatus(str, Enum):
    PENDING = "pending"
    IN_PROGRESS = "in_progress"
    PASSED = "passed"
    FAILED = "failed"
    TIMED_OUT = "timed_out"


class ChallengeEngine:
    """
    State machine that manages a single liveness verification session.

    Usage
    -----
    >>> engine = ChallengeEngine(count=3, timeout=15)
    >>> engine.sequence
    ['Blink', 'Left', 'Smile']
    >>> engine.start()
    >>> engine.current_action
    'Blink'
    >>> engine.submit_action('Blink')   # True = correct
    >>> engine.submit_action('Smile')   # True if next expected
    >>> engine.submit_action('Left')    # True → status becomes PASSED
    """

    def __init__(
        self,
        count: int = settings.CHALLENGE_COUNT,
        timeout: int = settings.PANIC_TIMER_SECONDS,
    ):
        all_actions = list(ChallengeAction)
        self.sequence: list[str] = [
            a.value for a in random.sample(all_actions, k=min(count, len(all_actions)))
        ]
        self.timeout = timeout
        self._current_index = 0
        self._start_time: Optional[float] = None
        self.status = ChallengeStatus.PENDING
        self.results: list[bool] = []

    # ── Properties ────────────────────────────────────────────────────────

    @property
    def current_action(self) -> Optional[str]:
        """Return the currently expected action, or None if complete/failed."""
        if self.status not in (ChallengeStatus.PENDING, ChallengeStatus.IN_PROGRESS):
            return None
        if self._current_index >= len(self.sequence):
            return None
        return self.sequence[self._current_index]

    @property
    def remaining_time(self) -> float:
        """Seconds remaining on the panic timer; 0 if not started or expired."""
        if self._start_time is None:
            return float(self.timeout)
        elapsed = time.monotonic() - self._start_time
        return max(0.0, self.timeout - elapsed)

    @property
    def is_timed_out(self) -> bool:
        return self._start_time is not None and self.remaining_time <= 0

    @property
    def progress(self) -> dict:
        """Snapshot for sending over WebSocket."""
        return {
            "sequence": self.sequence,
            "current_index": self._current_index,
            "current_action": self.current_action,
            "remaining_time": round(self.remaining_time, 1),
            "results": self.results,
            "status": self.status.value,
        }

    # ── Control ───────────────────────────────────────────────────────────

    def start(self) -> dict:
        """Begin the challenge; starts the panic timer."""
        self._start_time = time.monotonic()
        self.status = ChallengeStatus.IN_PROGRESS
        return self.progress

    def submit_action(self, detected_action: str) -> bool:
        """
        Submit a detected facial action from the biometric engine.

        Returns True if the action matched the expected one.
        If wrong action → immediate FAIL.
        If timed out → TIMED_OUT.
        """
        # Check timer first
        if self.is_timed_out:
            self.status = ChallengeStatus.TIMED_OUT
            return False

        if self.status != ChallengeStatus.IN_PROGRESS:
            return False

        expected = self.current_action
        if expected is None:
            return False

        if detected_action != expected:
            # Temporal logic: wrong order = instant failure
            self.status = ChallengeStatus.FAILED
            self.results.append(False)
            return False

        # Correct action
        self.results.append(True)
        self._current_index += 1

        # Check if all actions completed
        if self._current_index >= len(self.sequence):
            self.status = ChallengeStatus.PASSED

        return True

    def to_dict(self) -> dict:
        """Serialisable representation for database storage."""
        return {
            "sequence": self.sequence,
            "results": self.results,
            "status": self.status.value,
            "timeout": self.timeout,
        }
