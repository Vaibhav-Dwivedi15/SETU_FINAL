"""
Database models for raw packets.

Every packet received at /ingest (emergency or termination) is stored
here permanently, unmodified, as raw evidence -- regardless of whether it
later gets merged, rejected, or duplicates something else.

Column names mirror the frozen mesh packet spec (Section 3 of the
project handoff) as closely as SQLAlchemy/Python allow, so there's no
translation layer to keep in sync between what the mesh sends and what
gets stored.
"""

import enum
from sqlalchemy import ForeignKey
from sqlalchemy import Column, String, Integer, Float, DateTime, Enum as SAEnum, JSON
from sqlalchemy.sql import func

from app.db.base import Base


class PacketStatus(str, enum.Enum):
    RECEIVED = "RECEIVED"
    VALIDATED = "VALIDATED"
    REJECTED_SIGNATURE = "REJECTED_SIGNATURE"
    EXPIRED = "EXPIRED"
    MERGED = "MERGED"


class RawPacket(Base):
    __tablename__ = "raw_packets"

    id = Column(Integer, primary_key=True, index=True)
    incident_id = Column(Integer, ForeignKey("incidents.id"), nullable=True, index=True)

    packet_id = Column(String, unique=True, index=True, nullable=False)
    sender_id = Column(String, nullable=False)
    type = Column(String, nullable=False)  # "emergency" or "termination"
    timestamp = Column(String, nullable=False)  # ISO 8601, stored as-received
    nonce = Column(String, nullable=False)
    ttl = Column(Integer, nullable=False)
    hop_count = Column(Integer, nullable=False)
    protocol_version = Column(Integer, nullable=False)
    signature = Column(String, nullable=False)

    # EmergencyPacket-only fields
    emergency_id = Column(String, nullable=True, index=True)
    latitude = Column(Float, nullable=True)
    longitude = Column(Float, nullable=True)
    message = Column(String, nullable=True)
    priority = Column(String, nullable=True)

    # NOT part of the frozen mesh spec -- see app/schemas/packet.py
    # module docstring for why this is still here and nullable.
    incident_type = Column(String, nullable=True)

    # TerminationPacket-only field. Structurally stored only -- NOT
    # currently checked against a trusted responder registry. See
    # app/schemas/packet.py docstring for the known gap.
    responder_id = Column(String, nullable=True)

    relay_path = Column(JSON, nullable=True)  # list of hashed relay IDs, if present

    status = Column(SAEnum(PacketStatus), default=PacketStatus.RECEIVED, nullable=False)

    received_at = Column(DateTime(timezone=True), server_default=func.now())