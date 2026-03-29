# Fabio — Dynamic Anti-Spoofing Biometric FinTech App

> Active Liveness verification using Randomized Challenge-Response Sequences
> to prevent deepfake and presentation attacks during high-value money transfers.

## Tech Stack

| Layer | Technology |
|---|---|
| **Frontend** | Flutter (iOS + Android) |
| **Backend** | FastAPI (Python 3.9+) |
| **Database** | PostgreSQL + SQLAlchemy (async) |
| **Biometrics** | OpenCV + MediaPipe (468 3D landmarks) |
| **Communication** | REST APIs + WebSocket (real-time video) |
| **Deployment** | Docker + Docker Compose |

## Quick Start

### Backend

```bash
# Option 1: Docker (recommended)
docker compose up --build

# Option 2: Manual
cd backend
cp .env.example .env          # Edit with your DB credentials
pip install -r requirements.txt
uvicorn app.main:app --reload
```

API docs: `http://localhost:8000/docs`

### Frontend

```bash
cd frontend
flutter create .              # Scaffold platform directories
flutter pub get
flutter run
```

> ⚠️ After `flutter create .`, restore the `lib/` directory and `pubspec.yaml` 
> from the source code (they get overwritten with defaults).

## Architecture

```
Fabio/
├── backend/          ← FastAPI (22 REST + 1 WebSocket endpoint)
│   ├── app/
│   │   ├── models.py, database.py, config.py     ← Data layer
│   │   ├── auth.py, schemas.py                    ← Auth + validation
│   │   ├── liveness.py, challenge.py              ← Biometric engine
│   │   ├── main.py                                ← App + WebSocket
│   │   └── routers/                               ← 5 REST routers
│   └── Dockerfile
├── frontend/         ← Flutter (7 screens)
│   └── lib/
│       ├── screens/  ← splash, login, register, dashboard, transfer, liveness, settings
│       ├── services/ ← Dio REST + secure JWT storage
│       └── widgets/  ← GlassCard, FabButton
├── docker-compose.yml
└── DEPLOYMENT.md     ← Supabase + Render + Cloudflare + App Store guide
```

## Risk-Based Authentication Flow

1. User initiates a transfer
2. System checks amount against user's custom threshold
3. **Below threshold** → Standard PIN verification
4. **Above threshold** → Active Liveness camera flow:
   - Server generates random 3-action challenge (e.g., Blink → Smile → Turn Left)
   - App streams camera frames via WebSocket
   - MediaPipe extracts 468 facial landmarks
   - EAR detects blinks, MAR detects smiles, solvePnP detects head pose
   - Challenge engine enforces **strict temporal order** + **panic timer**
   - Result: PASS → transfer completes, FAIL → transfer rejected

## License

Private — Final Year Project
