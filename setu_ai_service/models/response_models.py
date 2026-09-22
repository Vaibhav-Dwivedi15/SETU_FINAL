"""
SETU AI - Response and Request Pydantic Schemas
"""

from typing import Optional, List
from pydantic import BaseModel, Field


class Coordinates(BaseModel):
    latitude: float
    longitude: float


class EmergencyRequest(BaseModel):
    emergency_id: str
    message: str
    relay_count: int = 0
    age_seconds: int = 0
    sender_id: Optional[str] = None
    location: Optional[Coordinates] = None


class DuplicateInfo(BaseModel):
    is_duplicate: bool
    matched_cluster_id: str
    similarity: float
    reason: Optional[str] = None


class EmergencyResponse(BaseModel):
    emergency_id: str
    message: str
    incident: str
    urgency: str
    priority: str
    duplicate_info: DuplicateInfo
    ai_enhanced: bool = False
    gemini_note: Optional[str] = None
