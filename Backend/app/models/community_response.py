"""
Database model for community response actions -- Phase 3.

When a nearby SETU user sees a community alert (via GET /alerts/nearby,
see app/routers/alerts.py) and taps a response action ("I'm nearby",
"I can help", etc.), one row is recorded here.

One (incident_id, sender_id) pair maps to exactly ONE row -- if the same
sender responds again with a different action (e.g. "I'm nearby" then
later "Already responding"), the existing row is updated in place, not
duplicated. This keeps "how many distinct people are responding, and
with what latest status" a simple query, not a dedup problem.
"""
import enum
from sqlalchemy import Column, Integer, String, DateTime, Enum as SAEnum, ForeignKey, UniqueConstraint
from sqlalchemy.sql import func
from app.db.base import Base


class ResponseType(str, enum.Enum):
    NEARBY = "NEARBY"                                   # "I'm nearby"
    CAN_HELP = "CAN_HELP"                                # "I can help"
    ALREADY_RESPONDING = "ALREADY_RESPONDING"            # "Already responding"
    CALLED_EMERGENCY_SERVICES = "CALLED_EMERGENCY_SERVICES"  # "Call emergency services"
    NAVIGATING = "NAVIGATING"                            # "Navigate to location"


class CommunityResponse(Base):
    __tablename__ = "community_responses"

    id = Column(Integer, primary_key=True, index=True)
    incident_id = Column(Integer, ForeignKey("incidents.id"), nullable=False, index=True)

    # Matches RawPacket.sender_id / UserProfile.sender_id -- NOT a full
    # profile join here. See app/routers/alerts.py: nothing in the
    # nearby-alert or response-recording path ever exposes the victim's
    # profile to a responding community member, or vice versa.
    sender_id = Column(String, nullable=False, index=True)

    response_type = Column(SAEnum(ResponseType), nullable=False)

    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())

    __table_args__ = (
        UniqueConstraint("incident_id", "sender_id", name="uq_community_response_incident_sender"),
    )
