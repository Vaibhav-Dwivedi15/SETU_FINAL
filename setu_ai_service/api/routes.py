"""
SETU AI - API Routes
"""

from fastapi import APIRouter
from pydantic import BaseModel
from models.response_models import (
    EmergencyRequest,
    EmergencyResponse,
    DamageAssessment,
    ResourceAssessment,
    MissingPersonAssessment,
)
from models.pipeline import process_message
from models.disaster_intelligence import (
    extract_damage_info,
    extract_resource_info,
    extract_missing_person_info,
)

router = APIRouter()


class TextPayload(BaseModel):
    message: str


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


@router.post("/analyze/damage", response_model=DamageAssessment)
def analyze_damage(payload: TextPayload):
    return extract_damage_info(payload.message)


@router.post("/analyze/resources", response_model=ResourceAssessment)
def analyze_resources(payload: TextPayload):
    return extract_resource_info(payload.message)


@router.post("/analyze/missing-person", response_model=MissingPersonAssessment)
def analyze_missing_person(payload: TextPayload):
    return extract_missing_person_info(payload.message)
