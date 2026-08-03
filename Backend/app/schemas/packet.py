"""
Packet schema.

Defines the shape of packets received at /ingest -- both emergency and
termination types, single or batched. This MUST match the frozen mesh
packet spec (Section 3 of the SETU project handoff) exactly, since these
are the packets Vaibhav's mesh layer actually produces and signs.

Known gap (flag, don't silently paper over): the frozen mesh spec's
EmergencyPacket does NOT carry `incident_type` -- only `message` and
`priority`. incident_type is kept here as an Optional field so it can
still be set directly (e.g. by tests, or later by Vaishnavi's AI triage
service after classifying the message), but real mesh devices will not
send it. incident_service.py falls back to keyword classification when
absent. Confirm with Vaibhav + Vaishnavi whether triage should backfill
this before dedup runs.
"""

from enum import Enum
from typing import Optional, List

from pydantic import BaseModel, Field


class IncidentType(str, Enum):
    FIRE = "fire"
    STAMPEDE = "stampede"
    LANDSLIDE = "landslide"
    FLOOD = "flood"
    MEDICAL = "medical"
    TRAPPED = "trapped"
    STRUCTURAL_COLLAPSE = "structural_collapse"
    OTHER = "other"


class PacketType(str, Enum):
    """
    Matches the frozen mesh spec's `type` field exactly.
    emergency   = a new/corroborating emergency report.
    termination = signals that a previously reported emergency is resolved.
    """
    EMERGENCY = "emergency"
    TERMINATION = "termination"


class PriorityLevel(str, Enum):
    """Matches EmergencyPacket.priority in the frozen mesh spec."""
    LOW = "low"
    MEDIUM = "medium"
    HIGH = "high"
    CRITICAL = "critical"


class PacketIn(BaseModel):
    """
    A single packet as received at /ingest, either standalone or as part
    of a batch (delayed sync). Field names/types mirror the frozen mesh
    packet spec (Section 3) exactly -- do not rename these without
    syncing with Vaibhav, since any mismatch breaks real device ingest.
    """

    # --- Common fields (every packet type) ---
    packet_id: str
    sender_id: str
    type: PacketType
    timestamp: str  # ISO 8601, e.g. "2026-08-01T12:00:00.000Z"
    nonce: str
    ttl: int = Field(..., ge=0, le=5)  # frozen spec: default/max = 5
    hop_count: int = Field(..., ge=0)
    protocol_version: int = Field(..., ge=1)
    signature: str

    # --- EmergencyPacket-only fields ---
    emergency_id: Optional[str] = None
    latitude: Optional[float] = None  # 0.0 fallback if GPS unavailable, per spec
    longitude: Optional[float] = None
    message: Optional[str] = None
    priority: Optional[PriorityLevel] = None

    # NOT part of the frozen mesh spec -- mesh devices do not send this.
    # Kept optional for internal/testing use and possible future AI
    # triage backfill. See module docstring.
    incident_type: Optional[IncidentType] = None

    # --- TerminationPacket-only fields ---
    # For termination packets, this is the emergency_id being closed.
    # responder_id itself is display-only metadata (e.g. a badge number)
    # and is NOT used for authorization -- confirmed with Vaibhav that
    # auth checks sender_id instead (the cryptographically-signed
    # field), since responder_id can be set to any string. See
    # responder_service.is_authorized_responder().
    responder_id: Optional[str] = None

    # Not part of the frozen spec's sample packet, but harmless to accept
    # if a future mesh version starts sending it.
    relay_path: Optional[List[str]] = None


class PacketBatchIn(BaseModel):
    """
    Wrapper for delayed sync -- a device that regained connectivity sends
    every packet it queued while offline in one request.
    """
    packets: List[PacketIn]