"""
SETU AI - Response and Request Pydantic Schemas
"""

from typing import Optional, List, Dict, Any
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


class DamageAssessment(BaseModel):
    has_damage: bool = False
    asset_type: Optional[str] = None  # e.g., Building, Bridge, Road, Hospital, School
    severity: str = "NONE"             # NONE, MINOR, MODERATE, SEVERE, CATASTROPHIC
    estimated_affected: Optional[int] = None
    details: Optional[str] = None


class ResourceAssessment(BaseModel):
    needs_resources: bool = False
    categories: List[str] = []         # Food, Water, Medical, Shelter, Clothing, Power
    urgency: str = "STANDARD"          # IMMEDIATE, HIGH, STANDARD
    details: Optional[str] = None


class MissingPersonAssessment(BaseModel):
    is_missing_report: bool = False
    name: Optional[str] = None
    age: Optional[int] = None
    gender: Optional[str] = None
    last_seen: Optional[str] = None


class EmergencyResponse(BaseModel):
    emergency_id: str
    message: str
    incident: str
    urgency: str
    priority: str
    duplicate_info: DuplicateInfo
    damage_assessment: Optional[DamageAssessment] = None
    resource_assessment: Optional[ResourceAssessment] = None
    missing_person_assessment: Optional[MissingPersonAssessment] = None
    ai_enhanced: bool = False
    gemini_note: Optional[str] = None
