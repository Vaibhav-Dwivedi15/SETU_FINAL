"""
Incident response schemas -- what the dashboard sees.
"""

from datetime import datetime
from typing import List, Optional

from pydantic import BaseModel, ConfigDict


class IncidentOut(BaseModel):
    """
    Authoritative incident view for the responder dashboard (Block 2).

    Every field the dashboard reads is produced HERE; the dashboard no longer
    has to guess or default them. sender_priority (what the reporter declared)
    and ai_priority (what the AI assessed) are deliberately separate and never
    merged; display_priority is the backend's single rule for the one label the
    UI colours/sorts/alerts on (AI assessment first, then the declared priority,
    else "Medium").
    """
    id: int
    incident_type: str
    latitude: float
    longitude: float
    status: str
    hop_count: Optional[int] = None
    relay_path: Optional[List[str]] = None

    sender_priority: Optional[str] = None
    ai_incident_type: Optional[str] = None
    ai_incident_confidence: Optional[float] = None
    ai_incident_explanation: Optional[str] = None
    ai_urgency: Optional[int] = None
    ai_urgency_confidence: Optional[float] = None
    ai_urgency_explanation: Optional[str] = None
    ai_priority: Optional[float] = None
    display_priority: str = "Medium"  # Critical | High | Medium | Low

    report_count: int = 1  # independent reports merged into this incident

    created_at: datetime
    updated_at: Optional[datetime] = None
    closed_at: Optional[datetime] = None

    model_config = ConfigDict(from_attributes=True)


class ProfileOut(BaseModel):
    sender_id: str
    name: str
    age: Optional[int] = None
    gender: Optional[str] = None
    medical_history: Optional[str] = None
    emergency_contacts: list[str] = []

    model_config = ConfigDict(from_attributes=True)


class AuditLogOut(BaseModel):
    """One entry in an incident's audit trail (CREATED/MERGED/CLOSED)."""
    id: int
    action: str
    packet_id: Optional[str] = None
    detail: Optional[str] = None
    created_at: datetime

    model_config = ConfigDict(from_attributes=True)
