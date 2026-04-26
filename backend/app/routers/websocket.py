from fastapi import APIRouter, WebSocket
from app.liveness import liveness_engine

router = APIRouter(tags=["WebSocket"])

@router.websocket("/ws/liveness")
async def liveness_websocket(websocket: WebSocket):
    await liveness_engine.connect(websocket)
    await liveness_engine.run_challenge(websocket)
    liveness_engine.disconnect(websocket)
