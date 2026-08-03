from fastapi import APIRouter
from pydantic import BaseModel

from models.pipeline import process_message

router = APIRouter()


class EmergencyRequest(BaseModel):
    emergency_id: str
    message: str
    relay_count: int = 0
    age_seconds: int = 0


@router.get("/")
def home():
    return {"project": "SETU AI Service", "status": "Running"}


@router.post("/analyze")
def analyze(request: EmergencyRequest):
    return process_message(
        message=request.message,
        relay_count=request.relay_count,
        age_seconds=request.age_seconds,
        emergency_id=request.emergency_id,
    )
