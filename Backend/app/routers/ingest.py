"""
POST /ingest -- receives a batch of packets from a device that has
regained connectivity after mesh-relaying offline.

Every packet in the batch is validated and stored independently -- one
bad packet in a batch of ten must not block the other nine. Response
reports per-packet outcome so the client (mobile/mesh device) knows
exactly what was accepted vs rejected and why.

Per-packet pipeline: duplicate check -> TTL check -> signature check ->
store raw packet -> route by type:
  emergency   -> AI analysis (incident type / urgency / priority --
                 non-blocking, never breaks ingestion if it fails) ->
                 incident_service.handle_sos_packet (dedup + create/merge
                 + SMS notification on genuinely new incidents)
  termination -> responder authorization check (against packet.sender_id,
                 NOT packet.responder_id -- see responder_service.py),
                 then incident_service.close_incident_by_emergency_id

AI INTEGRATION NOTE (updated -- decision REVERSED since Day 5/6): the
AI service's is_duplicate/matched_cluster_id is now the source of truth
for "is this a duplicate," replacing this backend's own
find_matching_incident() (the original Day 5/6 decision kept the
backend's own dedup as primary and ignored the AI's -- see git history
if you need that reasoning). find_matching_incident() is kept as a
FALLBACK ONLY, used when the AI call fails/is unavailable for a given
request -- see app/services/incident_service.py's handle_sos_packet and
app/services/ai_analysis_service.py's module docstring for the full
history and the operational risk that comes with this (AI dedup's
cluster state is in-memory, resets on restart).

NOTE on the authorization check: the packet is already stored as raw
evidence (status=VALIDATED) by the time authorization is checked --
being an unauthorized sender doesn't mean the packet itself was
malformed, it means the *action* it requested (closing an incident)
isn't honored. That distinction matters for the audit trail.

PERFORMANCE NOTE (load test, Aug 2): the raw packet store now uses
flush(), not commit() -- it only needs to exist/have an ID within this
request's transaction so incident_service can link to it. The actual
commit happens once, inside handle_sos_packet / close_incident_by_emergency_id,
so each accepted packet does ONE fsync total instead of several.
Duplicate/expired/rejected-signature packets still commit immediately,
since those are terminal outcomes with no further work in this request.
"""

from fastapi import APIRouter, Depends
from datetime import datetime, timezone
from sqlalchemy.orm import Session

from app.db.base import get_db
from app.models.packet import RawPacket, PacketStatus
from app.schemas.packet import PacketBatchIn, PacketType
from app.services.validation_service import is_ttl_expired, is_duplicate
from app.services.signature_service import verify_signature
from app.services.incident_service import handle_sos_packet, close_incident_by_emergency_id
from app.services.responder_service import is_authorized_responder
from app.services.ai_analysis_service import analyze as ai_analyze

router = APIRouter()


def _build_raw_packet(packet, status: PacketStatus) -> RawPacket:
    """
    Shared constructor so the enum-to-string conversion (type,
    incident_type, priority) only lives in one place.
    """
    return RawPacket(
        **packet.model_dump(exclude={"incident_type", "type", "priority"}),
        incident_type=packet.incident_type.value if packet.incident_type else None,
        type=packet.type.value,
        priority=packet.priority.value if packet.priority else None,
        status=status,
    )


@router.post("/ingest")
def ingest_packets(batch: PacketBatchIn, db: Session = Depends(get_db)):
    accepted = []
    rejected = []

    for packet in batch.packets:
        if is_duplicate(db, packet):
            rejected.append({
                "packet_id": packet.packet_id,
                "reason": "duplicate packet_id",
            })
            continue

        if is_ttl_expired(packet):
            db.add(_build_raw_packet(packet, PacketStatus.EXPIRED))
            db.commit()
            rejected.append({
                "packet_id": packet.packet_id,
                "reason": "TTL expired",
            })
            continue

        if not verify_signature(packet):
            db.add(_build_raw_packet(packet, PacketStatus.REJECTED_SIGNATURE))
            db.commit()
            rejected.append({
                "packet_id": packet.packet_id,
                "reason": "invalid signature",
            })
            continue

        db_packet = _build_raw_packet(packet, PacketStatus.VALIDATED)
        db.add(db_packet)
        db.flush()  # visible within this transaction; committed once below

        if packet.type == PacketType.EMERGENCY:
            # age_seconds: how long ago this packet was originally created,
            # per setu_ai_service's own field-mapping doc -- clamped to
            # never go negative (clock skew between devices). AI analysis
            # never blocks/breaks ingestion: ai_analyze() swallows its own
            # failures and returns None, and handle_sos_packet treats None
            # exactly like "no AI fields yet."
            age_seconds = int(
                datetime.now(timezone.utc).timestamp()
                - datetime.fromisoformat(packet.timestamp).timestamp()
            )
            ai_result = ai_analyze(
                message=packet.message,
                emergency_id=packet.emergency_id,
                relay_count=packet.hop_count,
                age_seconds=max(age_seconds, 0),
                latitude=packet.latitude if packet.latitude is not None else 0.0,
                longitude=packet.longitude if packet.longitude is not None else 0.0,
            )

            incident = handle_sos_packet(db, packet, ai_result=ai_result)  # commits once internally
            accepted.append({
                "packet_id": packet.packet_id,
                "incident_id": incident.id,
            })

        elif packet.type == PacketType.TERMINATION:
            if not is_authorized_responder(db, packet.sender_id):
                db.commit()  # still commit the stored raw packet even though the action is rejected
                rejected.append({
                    "packet_id": packet.packet_id,
                    "reason": "unauthorized responder",
                })
                continue

            closed_incident = close_incident_by_emergency_id(db, packet.emergency_id)  # commits once internally
            accepted.append({
                "packet_id": packet.packet_id,
                "closed_incident_id": closed_incident.id if closed_incident else None,
            })

    return {"accepted": accepted, "rejected": rejected}