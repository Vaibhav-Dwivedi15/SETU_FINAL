"""
Schemas for the nearby community alert + response-action endpoints
(Phase 3). Kept separate from schemas/incident.py and schemas/packet.py
since these shapes are public-mobile-app-facing, not mesh-packet-facing
or responder-dashboard-facing.
"""
from datetime import datetime
from typing import Optional

from pydantic import BaseModel, Field, ConfigDict

from app.models.community_response import ResponseType


class NearbyIncidentOut(BaseModel):
    """
    One row of GET /alerts/nearby -- deliberately excludes any reporter
    identity/profile field. See nearby_alert_service.py's module
    docstring for the privacy reasoning.
    """
    incident_id: int
    incident_type: str
    sender_priority: Optional[str] = None
    ai_priority: Optional[float] = None
    distance_km: float
    created_at: datetime
    message: str

    model_config = ConfigDict(from_attributes=True)


class RespondIn(BaseModel):
    sender_id: str
    response_type: ResponseType


class CommunityResponseOut(BaseModel):
    id: int
    incident_id: int
    sender_id: str
    response_type: ResponseType
    created_at: datetime
    updated_at: datetime

    model_config = ConfigDict(from_attributes=True)
