# ──────────────────────────────────────────────────────────────────────────────
#  Fabio Backend — Dockerfile
# ──────────────────────────────────────────────────────────────────────────────
#  Multi-purpose: dev + prod (override CMD for development).
#  Image ≈ 450 MB — python:3.9-slim + OpenCV system deps.
# ──────────────────────────────────────────────────────────────────────────────

FROM python:3.11-slim

# Prevent Python from writing .pyc files & enable unbuffered stdout/stderr
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

# System dependencies required by OpenCV, MediaPipe & Bcrypt
RUN apt-get update && apt-get install -y --no-install-recommends \
        gcc \
        python3-dev \
        libgl1 \
        libglib2.0-0t64 \
        libsm6 \
        libxext6 \
        libxrender1 \
    && rm -rf /var/lib/apt/lists/*

# Working directory
WORKDIR /app

# Install Python dependencies (cached layer — only re-runs when requirements change)
COPY requirements.txt .
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir -r requirements.txt

# Copy application source
COPY . .

# Default port (Railway overrides via $PORT env var)
ENV PORT=8000
EXPOSE $PORT

# Run with Uvicorn — 0.0.0.0 for container networking, workers=1 for WebSocket
CMD ["sh", "-c", "uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8000} --workers 1"]
