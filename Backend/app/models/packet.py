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
from sqlalchemy import ForeignKey, UniqueConstraint, Index
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
    """
    Only AUTHENTICATED, ACCEPTED packets live here (Block 2). Rejected
    packets (bad signature, stale, malformed, ...) are recorded in
    RejectedPacket instead, so junk can never occupy a packet_id.

    IDENTITY (Block 2, packet-ID squatting fix): a packet is identified by
    (sender_id, packet_id). sender_id is the Ed25519 public key and the
    signature was verified against it BEFORE this row is written, so the pair
    cannot be claimed by anyone but the key holder. The previous UNIQUE on
    packet_id alone let anyone who saw a packet_id on the mesh submit a
    packet with that id first and make the genuine one answer "duplicate".
    packet_id keeps a plain (non-unique) index for lookups.
    """
    __tablename__ = "raw_packets"
    __table_args__ = (
        UniqueConstraint("sender_id", "packet_id", name="uq_raw_packets_sender_packet"),
    )

    id = Column(Integer, primary_key=True, index=True)
    incident_id = Column(Integer, ForeignKey("incidents.id"), nullable=True, index=True)

    packet_id = Column(String, index=True, nullable=False)
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


class RejectedPacket(Base):
    """
    Audit trail of packets /ingest refused. Deliberately NOT unique on
    packet_id and NOT consulted by dedup: a rejected packet has no standing.
    Only metadata is kept (no message/location) and every text field is
    truncated, so this table cannot be used as free storage.
    """
    __tablename__ = "rejected_packets"

    id = Column(Integer, primary_key=True, index=True)
    packet_id = Column(String(64), nullable=True, index=True)
    sender_id = Column(String(64), nullable=True)
    code = Column(String(48), nullable=False)
    reason = Column(String(200), nullable=True)
    received_at = Column(DateTime(timezone=True), server_default=func.now())
