"""
Incident response schemas -- what the dashboard sees.
"""

from datetime import datetime
from typing import Optional

from pydantic import BaseModel


class IncidentOut(BaseModel):
    id: int
    incident_type: str
    latitude: float
    longitude: float
    status: str
    hop_count: Optional[int] = None
    created_at: datetime
    closed_at: Optional[datetime] = None

    class Config:
        from_attributes = True


class ProfileOut(BaseModel):
    sender_id: str
    name: str
    age: Optional[int] = None
    gender: Optional[str] = None
    medical_history: Optional[str] = None
    emergency_contacts: list[str] = []

    class Config:
        from_attributes = True


class AuditLogOut(BaseModel):
    """One entry in an incident's audit trail (CREATED/MERGED/CLOSED)."""
    action: str
    packet_id: Optional[str] = None
    detail: Optional[str] = None
    created_at: datetime

    class Config:
        from_attributes = True