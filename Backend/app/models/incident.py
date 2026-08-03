"""
Database model for incidents.

An Incident represents one real-world emergency event, built up from one
or more raw packets (deduplication merges multiple SOS reports into a
single incident). Termination packets close an incident -- they never
delete it, so dashboard history/audit stays intact.
"""

import enum

from sqlalchemy import Column, String, Integer, Float, DateTime, Enum as SAEnum, JSON
from sqlalchemy.sql import func

from app.db.base import Base


class IncidentStatus(str, enum.Enum):
    OPEN = "OPEN"
    CLOSED = "CLOSED"


class Incident(Base):
    __tablename__ = "incidents"

    id = Column(Integer, primary_key=True, index=True)

    incident_type = Column(String, nullable=False)
    latitude = Column(Float, nullable=False)
    longitude = Column(Float, nullable=False)

    status = Column(SAEnum(IncidentStatus), default=IncidentStatus.OPEN, nullable=False)

    # Relay metadata for the Dashboard team -- hop count of the earliest
    # report, and any relay path info available at incident-creation time.
    hop_count = Column(Integer, nullable=True)
    relay_path = Column(JSON, nullable=True)

    # Sender-declared priority, straight from the packet's own `priority`
    # field ("low"/"medium"/"high"/"critical") -- kept distinct from the
    # AI-computed ai_priority below. NEVER let one silently overwrite the
    # other; they answer different questions (what the reporter said vs.
    # what the AI assessed) and both are shown on the dashboard.
    sender_priority = Column(String, nullable=True)

    # AI fields (Vaishnavi's setu_ai_service, wired in Day 5/6). All
    # nullable so incident creation never depends on the AI call
    # succeeding -- see app/services/ai_analysis_service.py, which
    # swallows AI-side failures and returns None rather than raising.
    ai_incident_type = Column(String, nullable=True)
    ai_incident_confidence = Column(Float, nullable=True)
    ai_incident_explanation = Column(String, nullable=True)
    ai_urgency = Column(Integer, nullable=True)  # 1-5
    ai_urgency_confidence = Column(Float, nullable=True)
    ai_urgency_explanation = Column(String, nullable=True)
    ai_priority = Column(Float, nullable=True)  # 1.0-5.0, AI-assessed -- distinct from sender_priority above

    created_at = Column(DateTime(timezone=True), server_default=func.now())
    closed_at = Column(DateTime(timezone=True), nullable=True)
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())