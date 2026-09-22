"""
SETU AI - API Routes
"""

from fastapi import APIRouter
from models.response_models import EmergencyRequest, EmergencyResponse
from models.pipeline import process_message

router = APIRouter()


@router.get("/")
def home():
    return {"project": "SETU AI Service", "status": "Running"}


@router.post("/analyze", response_model=EmergencyResponse)
def analyze(request: EmergencyRequest):
    lat = request.location.latitude if request.location else None
    lon = request.location.longitude if request.location else None

    result = process_message(
        message=request.message,
        relay_count=request.relay_count,
        age_seconds=request.age_seconds,
        emergency_id=request.emergency_id,
        latitude=lat,
        longitude=lon,
    )
    return result
