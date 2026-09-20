"""
User profile model.

Stores full sender identity/medical info, collected once at registration
time over normal internet (never over mesh). Mesh packets only ever carry
sender_id -- this table is the only place full profile data lives, and
it's only ever exposed via the responder-authenticated
GET /incidents/{id}/profile endpoint, never through /ingest or any
mesh-facing path.
"""

from sqlalchemy import Column, String, Integer, JSON, DateTime
from sqlalchemy.sql import func

from app.db.base import Base


class UserProfile(Base):
    __tablename__ = "user_profiles"

    id = Column(Integer, primary_key=True, index=True)

    # Matches RawPacket.sender_id -- the only link between mesh data and
    # this profile. Unique because one device/sender = one profile.
    sender_id = Column(String, unique=True, index=True, nullable=False)

    name = Column(String, nullable=False)
    age = Column(Integer, nullable=True)
    gender = Column(String, nullable=True)
    medical_history = Column(String, nullable=True)

    # List of phone numbers, stored as JSON array. Used by the SMS
    # gateway integration to notify contacts when a new incident is
    # created for this sender.
    emergency_contacts = Column(JSON, nullable=True)

    created_at = Column(DateTime(timezone=True), server_default=func.now())