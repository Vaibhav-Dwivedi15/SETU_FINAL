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
from typing import Optional, List, Dict, Any
from pydantic import BaseModel, Field, field_validator


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

    SEP 2026 SECURITY HARDENING: the mesh side already treats every
    incoming packet as untrusted and bounds it (PacketValidator,
    SecurityConstants.maxPacketSize) -- but /ingest is a separate,
    independently-reachable HTTP endpoint. PacketBatchIn.packets is
    List[Dict[str, Any]] specifically so one malformed packet doesn't
    422 a whole batch (see PacketBatchIn's docstring) -- which means
    Pydantic's normal "reject the whole request" validation-at-parse
    behavior doesn't apply here, and every field below needed its own
    explicit bound added. None of these change what a genuine mesh
    device sends (real values are all far inside these limits); they
    only reject what a genuine device could never produce.
    """
    # --- Common fields (every packet type) ---
    # 256 chars is generous headroom over a 64-hex-char Ed25519 public
    # key / packet id in practice, without hardcoding an exact length
    # that could break a future protocol version.
    packet_id: str = Field(..., min_length=1, max_length=256)
    sender_id: str = Field(..., min_length=1, max_length=256)
    type: PacketType
    # ISO 8601, e.g. "2026-08-01T12:00:00.000Z". Bounded, not otherwise
    # validated here -- is_ttl_expired() already treats an unparseable
    # timestamp as expired (fail closed), so a malformed-but-short
    # string is rejected downstream, not accepted.
    timestamp: str = Field(..., min_length=1, max_length=64)
    nonce: str = Field(..., min_length=1, max_length=128)
    ttl: int = Field(..., ge=0, le=5)  # frozen spec: default/max = 5
    hop_count: int = Field(..., ge=0, le=1000)
    protocol_version: int = Field(..., ge=1)
    # Ed25519 signatures are a fixed 64 bytes (128 hex chars); 512 is
    # headroom, not a claim about signature length.
    signature: str = Field(..., min_length=1, max_length=512)
    # --- EmergencyPacket-only fields ---
    emergency_id: Optional[str] = Field(default=None, max_length=256)
    # Real-world bounds, not the frozen spec's "any float" -- an
    # out-of-range coordinate cannot correspond to a real device
    # location and would otherwise flow straight into incident
    # geolocation and dedup distance math (see deduplication_service.py's
    # haversine_distance_meters, which assumes valid lat/lon).
    latitude: Optional[float] = Field(default=None, ge=-90, le=90)
    longitude: Optional[float] = Field(default=None, ge=-180, le=180)
    # Emergency message text. 2000 chars is far beyond what the mesh's
    # own compact-packet design (SecurityConstants.maxPacketSize = 4096
    # bytes for the WHOLE packet) could ever carry -- bounding it here
    # stops an attacker who skips the mesh entirely and POSTs straight
    # to /ingest from stuffing an arbitrarily large string into storage,
    # AI analysis, and (eventually) the dashboard's incident view.
    message: Optional[str] = Field(default=None, max_length=2000)
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
    responder_id: Optional[str] = Field(default=None, max_length=256)
    # Not part of the frozen spec's sample packet, but harmless to accept
    # if a future mesh version starts sending it. Bounded on both list
    # length and per-entry length -- an unbounded relay_path is exactly
    # the kind of field an attacker who bypasses the mesh's own hop-count
    # limits could otherwise inflate without limit.
    relay_path: Optional[List[str]] = Field(default=None, max_length=32)

    @field_validator("relay_path")
    @classmethod
    def _bound_relay_path_entries(cls, value: Optional[List[str]]) -> Optional[List[str]]:
        if value is None:
            return value
        for hop in value:
            if len(hop) > 256:
                raise ValueError("relay_path entry exceeds 256 characters")
        return value


class PacketBatchIn(BaseModel):
    """
    Wrapper for delayed sync -- a device that regained connectivity sends
    every packet it queued while offline in one request.

    IMPORTANT (fixed Aug 2026 -- confirmed root cause of "one bad packet
    kills the whole batch"): `packets` is intentionally List[Dict[str, Any]],
    NOT List[PacketIn]. If it were List[PacketIn], FastAPI/Pydantic would
    validate every packet in the batch at the HTTP-body-parsing stage,
    BEFORE the router function ever runs -- meaning one malformed packet
    anywhere in a batch of ten would 422 the entire batch, contradicting
    this router's own per-packet-independence contract (see ingest.py
    module docstring). Each raw dict is instead validated individually
    inside ingest_packets(), so a bad packet is rejected on its own and
    the other nine still process normally.

    SEP 2026 SECURITY HARDENING: `packets` had no upper bound, so a
    single request could carry an arbitrarily large batch -- each entry
    still an untyped dict at this stage, so the real cost (JSON parsing,
    the per-packet loop, one DB round-trip per packet in ingest.py) is
    paid before any per-packet validation runs. 500 is generous headroom
    over the largest batch a real device would ever accumulate offline
    (LocalQueueService's own maxRelayQueue is 500) while still bounding
    the request to something FastAPI/Starlette can parse and this
    endpoint can process without becoming a flood vector in its own
    right (session brief: "protect ... backend ingestion ... against
    packet floods").
    """
    packets: List[Dict[str, Any]] = Field(..., max_length=500)
