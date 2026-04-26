from fastapi import WebSocket, WebSocketDisconnect
import asyncio
import random
import json
from app.config import settings

class LivenessEngine:
    def __init__(self):
        self.active_connections: list[WebSocket] = []

    async def connect(self, websocket: WebSocket):
        await websocket.accept()
        self.active_connections.append(websocket)

    def disconnect(self, websocket: WebSocket):
        if websocket in self.active_connections:
            self.active_connections.remove(websocket)

    async def run_challenge(self, websocket: WebSocket):
        challenges = ["smirk", "blink", "turn_left", "turn_right"]
        
        try:
            for i in range(settings.CHALLENGE_COUNT):
                challenge = random.choice(challenges)
                await websocket.send_json({
                    "type": "challenge",
                    "step": i + 1,
                    "total": settings.CHALLENGE_COUNT,
                    "action": challenge
                })
                
                # Wait for frontend response
                data = await websocket.receive_text()
                response = json.loads(data)
                
                if response.get("status") != "success" or response.get("action") != challenge:
                    await websocket.send_json({"type": "result", "status": "failed", "reason": "Challenge failed"})
                    return
                
            await websocket.send_json({"type": "result", "status": "success"})
        except WebSocketDisconnect:
            self.disconnect(websocket)
        except Exception as e:
            if websocket in self.active_connections:
                await websocket.send_json({"type": "result", "status": "error", "message": str(e)})

liveness_engine = LivenessEngine()
