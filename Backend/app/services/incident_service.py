"""
Incident service.

Turns a validated emergency packet into either a new Incident or a
corroboration of an existing one, and closes incidents when a matching
termination packet arrives.

RawPacket.incident_id is the source of truth linking a stored packet to
its incident -- closing/lookup logic uses that direct link rather than
re-guessing by location, since two different incidents can share the
same coordinates over time (multiple fires at the same spot, etc.).

incident_type gap: the frozen mesh packet spec does NOT include
incident_type on EmergencyPacket (only message + priority) -- see
app/schemas/packet.py docstring. When absent, create_incident_from_packet
falls back to classification_service.infer_incident_type() (a keyword
stopgap), only defaulting to OTHER if that also finds nothing. Flag with
Vaishnavi whether real AI triage should eventually replace this inference
step -- if so, swap the call here, dedup logic doesn't need to change.

Every mutation here (create, merge, close) is recorded in
IncidentAuditLog via _log_incident_action, per project memory's "every
incident modification should be audited."

PERFORMANCE NOTE (load test, Aug 2): the original version of this file
committed up to 4 times per packet (raw packet store, incident
create/attach, incident_id link, audit log). Under 50 concurrent
requests, each commit() forces a Postgres fsync, so ~150-200 near-
simultaneous fsyncs were the real bottleneck (avg latency 8.5s, and it
got WORSE, not better, when the connection pool was enlarged -- proving
it wasn't a pool-size problem). Fixed by using db.flush() everywhere
that only needs an ID/visibility within the same transaction, and
committing ONCE per packet, at the very end of handle_sos_packet /
close_incident_by_emergency_id.

PHASE 2 NOTE (government notification adapter, Aug 2026): like SMS
notification, the government adapter call (notify_government, see
app/services/government_notification_service.py) fires AFTER commit /
advisory-lock-release, and ONLY for genuinely new incidents -- same
reasoning as SMS: never spam a duplicate government notification per
corroborating report, and never hold the per-incident-type lock open for
an external (even if currently mocked) network-shaped call. It is
strictly non-blocking: any failure is caught and logged inside
notify_government itself and can never affect the response returned to
the mesh device.
"""

from dataclasses import dataclass, field
from typing import Optional
from datetime import datetime, timezone
from sqlalchemy import text
import logging
import zlib
from sqlalchemy.orm import Session

from app.models.audit_log import IncidentAuditLog, AuditAction
from app.models.incident import Incident, IncidentStatus
from app.models.packet import RawPacket
from app.models.user_profile import UserProfile
from app.schemas.packet import PacketIn, IncidentType
from app.services.classification_service import infer_incident_type
from app.core.contract import AI_DEDUP_RADIUS_METERS
from app.services.deduplication_service import find_matching_incident, haversine_distance_meters, resolve_incident_type
from app.services.sms_service import notify_emergency_contacts, count_notified
from app.services.government_notification_service import notify_government


def _find_incident_by_emergency_id(db: Session, emergency_id: str) -> Optional[Incident]:
    """
    Looks up the Incident that emergency_id's ORIGINAL emergency packet
    is linked to, via RawPacket.incident_id -- same lookup pattern
    close_incident_by_emergency_id uses below. Used to resolve the AI
    service's matched_cluster_id (which IS an emergency_id, per its own
    handoff doc) into an actual Incident row.
    """
    original_packet = (
        db.query(RawPacket)
        .filter(RawPacket.emergency_id == emergency_id, RawPacket.type == "emergency")
        .order_by(RawPacket.id.asc())
        .first()
    )
    if not original_packet or not original_packet.incident_id:
        return None
    return db.query(Incident).filter(Incident.id == original_packet.incident_id).first()


def _log_incident_action(
    db: Session,
    incident_id: int,
    action: AuditAction,
    packet_id: str = None,
    detail: str = None,
    commit: bool = True,
) -> None:
    """
    commit=False lets callers batch this into their own single final
    commit for the whole packet, instead of fsyncing separately.
    """
    entry = IncidentAuditLog(
        incident_id=incident_id,
        action=action,
        packet_id=packet_id,
        detail=detail,
    )
    db.add(entry)
    if commit:
        db.commit()


def create_incident_from_packet(db: Session, packet: PacketIn, ai_result: Optional[dict] = None) -> Incident:
    """
    Creates a brand-new Incident from a packet that didn't match any
    existing OPEN incident. incident_type is taken from the packet if
    present, otherwise inferred from the message text, falling back to
    OTHER only if inference also can't tell.

    ai_result (from app.services.ai_analysis_service.analyze(), or None
    if the AI call failed/was skipped) supplies the ai_* fields below.
    sender_priority is always set from the packet's own declared
    priority, independent of whether AI analysis succeeded -- the two
    are deliberately separate columns (see Incident model docstring),
    never conflated.

    NOTE (open question, not yet decided): AI fields are only set here,
    at initial creation -- a later corroborating packet that merges into
    this incident does NOT currently re-run analysis or update these
    fields, even if e.g. urgency should escalate based on new
    information. Flag with the team before assuming that's fine long-term.

    Uses flush(), not commit() -- this incident's row needs to exist and
    have an ID within the current transaction (so refresh() and the
    caller's later work can use incident.id), but the actual fsync is
    deferred to the caller's single final commit.
    """
    incident_type = (
        packet.incident_type if packet.incident_type
        else infer_incident_type(packet.message)
    )

    incident = Incident(
        incident_type=incident_type.value if hasattr(incident_type, "value") else incident_type,
        latitude=packet.latitude if packet.latitude is not None else 0.0,
        longitude=packet.longitude if packet.longitude is not None else 0.0,
        hop_count=packet.hop_count,
        relay_path=packet.relay_path,
        sender_priority=packet.priority.value if packet.priority else None,
    )
    if ai_result:
        incident.ai_incident_type = ai_result.get("ai_incident_type")
        incident.ai_incident_confidence = ai_result.get("ai_incident_confidence")
        incident.ai_incident_explanation = ai_result.get("ai_incident_explanation")
        incident.ai_urgency = ai_result.get("ai_urgency")
        incident.ai_urgency_confidence = ai_result.get("ai_urgency_confidence")
        incident.ai_urgency_explanation = ai_result.get("ai_urgency_explanation")
        incident.ai_priority = ai_result.get("ai_priority")

    db.add(incident)
    db.flush()
    db.refresh(incident)
    return incident


@dataclass
class DedupDecision:
    """
    Explainable new-vs-merge decision (Block 2). The AI service PROPOSES a
    match; this backend decides, using facts it can verify itself (incident
    status, distance, category). The AI is never the sole source of truth for
    incident identity.

    decision: "NEW_INCIDENT" | "MERGED"
    reason  (stable machine code):
      no_ai_match                 AI found no similar recent report -> new incident
      ai_match_accepted           AI match, target OPEN, categories compatible,
                                  location consistent (or unverifiable, see evidence)
      ai_match_vetoed_closed      AI match pointed at a CLOSED incident -> not merged
      ai_match_vetoed_unresolved  AI cluster id has no incident in the database
      ai_match_vetoed_category    both reports have a definite, different category
      ai_match_vetoed_distance    backend-computed distance exceeds the dedup radius
      fallback_match / fallback_no_match
                                  AI unavailable (or its match was vetoed): the
                                  backend's own DB-backed OPEN-incident dedup
    """
    decision: str
    reason: str
    matched_incident_id: Optional[int] = None
    evidence: dict = field(default_factory=dict)

    def as_dict(self) -> dict:
        return {
            "dedup_decision": self.decision,
            "matched_incident_id": self.matched_incident_id,
            "dedup_reason": self.reason,
            "dedup_evidence": self.evidence,
        }

    def audit_detail(self) -> str:
        bits = [f"dedup={self.reason}"]
        if self.matched_incident_id is not None:
            bits.append(f"matched_incident={self.matched_incident_id}")
        for key in ("similarity", "match_method", "distance_meters"):
            if self.evidence.get(key) is not None:
                bits.append(f"{key}={self.evidence[key]}")
        return " ".join(bits)[:250]


@dataclass
class SosOutcome:
    incident: Incident
    is_new_incident: bool
    dedup: DedupDecision
    sms_contacts_notified: int = 0


def _has_gps(lat: Optional[float], lon: Optional[float]) -> bool:
    return lat is not None and lon is not None and not (lat == 0.0 and lon == 0.0)


def _definite(value: Optional[str]) -> Optional[str]:
    """Normalise a category; 'unknown'/'other'/empty carry no information."""
    if not value:
        return None
    value = str(value).strip().lower()
    return None if value in ("unknown", "other", "") else value


def _categories_conflict(incident: Incident, packet: PacketIn, ai_result: Optional[dict]) -> bool:
    ai_new = _definite((ai_result or {}).get("ai_incident_type"))
    ai_old = _definite(incident.ai_incident_type)
    if ai_new and ai_old and ai_new != ai_old:
        return True
    new_type = _definite(resolve_incident_type(packet))
    old_type = _definite(incident.incident_type)
    return bool(new_type and old_type and new_type != old_type)


def decide_dedup(db: Session, packet: PacketIn, ai_result: Optional[dict]) -> tuple[Optional[Incident], DedupDecision]:
    """Returns (incident to merge into or None, the explainable decision)."""
    evidence = {}
    if ai_result is not None:
        evidence = {
            "similarity": ai_result.get("similarity"),
            "match_method": ai_result.get("match_method"),
            "distance_meters": ai_result.get("distance_meters"),
        }

    if ai_result is None:
        fallback = find_matching_incident(db, packet)
        if fallback is not None:
            return fallback, DedupDecision("MERGED", "fallback_match", fallback.id, {"source": "db_fallback"})
        return None, DedupDecision("NEW_INCIDENT", "fallback_no_match", None, {"source": "db_fallback"})

    if not (ai_result.get("is_duplicate") and ai_result.get("matched_cluster_id")):
        return None, DedupDecision("NEW_INCIDENT", "no_ai_match", None, evidence)

    candidate = _find_incident_by_emergency_id(db, ai_result["matched_cluster_id"])
    veto = None
    if candidate is None:
        veto = "ai_match_vetoed_unresolved"
    elif candidate.status != IncidentStatus.OPEN:
        veto = "ai_match_vetoed_closed"
    elif _categories_conflict(candidate, packet, ai_result):
        veto = "ai_match_vetoed_category"
    elif _has_gps(packet.latitude, packet.longitude) and _has_gps(candidate.latitude, candidate.longitude):
        backend_distance = haversine_distance_meters(
            packet.latitude, packet.longitude, candidate.latitude, candidate.longitude
        )
        evidence["backend_distance_meters"] = round(backend_distance, 1)
        if backend_distance > AI_DEDUP_RADIUS_METERS:
            veto = "ai_match_vetoed_distance"

    if veto is None:
        if not _has_gps(packet.latitude, packet.longitude) or not _has_gps(candidate.latitude, candidate.longitude):
            evidence["location_verified"] = False  # text+time match only; one side had no GPS fix
        return candidate, DedupDecision("MERGED", "ai_match_accepted", candidate.id, evidence)

    # The AI proposed a merge the backend cannot support. Do NOT silently drop
    # into the closed/foreign incident; consult the backend's own OPEN-incident
    # dedup instead (which can still join a genuinely nearby OPEN incident, e.g.
    # the one a previous vetoed report just created).
    evidence["vetoed_incident_id"] = candidate.id if candidate is not None else None
    fallback = find_matching_incident(db, packet)
    if fallback is not None:
        evidence["ai_veto"] = veto
        return fallback, DedupDecision("MERGED", "fallback_match", fallback.id, evidence)
    return None, DedupDecision("NEW_INCIDENT", veto, None, evidence)


def process_sos_packet(db: Session, packet: PacketIn, ai_result: Optional[dict] = None) -> SosOutcome:
    """
    Attach to an existing OPEN incident if the dedup decision says so, else
    create a new one. Also links the already-stored RawPacket row to the
    resulting incident (RawPacket.incident_id), which is what makes closing
    an incident later an exact lookup instead of a location-based guess.

    See DedupDecision for the (explainable) decision rules. The AI service's
    duplicate proposal is used, but verified by the backend; the backend's own
    DB dedup is the fallback when the AI is unavailable or its proposal is
    vetoed. Never blend the two for the same packet without recording why.

    SMS: exactly once per NEW incident (never on merge), via the idempotent
    ledger in sms_service. Government adapter: same rule.

    RACE CONDITION FIX (load test, Aug 2): a Postgres advisory transaction lock,
    scoped per incident_type, serializes the check+create section so concurrent
    same-type packets can't each create their own incident. SMS and the
    government adapter run AFTER commit/lock release (a slow send must not hold
    the lock). The lock is Postgres-only (dialect guard) -- the race it prevents
    is untested on SQLite.
    """
    incident_type_for_lock = (
        packet.incident_type.value if packet.incident_type
        else infer_incident_type(packet.message).value
    )
    lock_key = zlib.crc32(incident_type_for_lock.encode())
    if db.get_bind().dialect.name == "postgresql":
        db.execute(text("SELECT pg_advisory_xact_lock(:key)"), {"key": lock_key})

    existing, decision = decide_dedup(db, packet, ai_result)

    is_new_incident = existing is None
    incident = existing if existing else create_incident_from_packet(db, packet, ai_result=ai_result)

    raw = (
        db.query(RawPacket)
        .filter(RawPacket.packet_id == packet.packet_id, RawPacket.sender_id == packet.sender_id)
        .first()
    )
    if raw:
        raw.incident_id = incident.id

    _log_incident_action(
        db, incident.id,
        AuditAction.CREATED if is_new_incident else AuditAction.MERGED,
        packet_id=packet.packet_id, detail=decision.audit_detail(), commit=False,
    )

    db.commit()  # releases the advisory lock here -- next same-type request can proceed now

    notified = 0
    if is_new_incident:
        notified = send_incident_notifications(db, incident, packet.sender_id)
        # Mock government adapter. Never blocking, never able to affect the response.
        notify_government(db, incident)

    return SosOutcome(incident=incident, is_new_incident=is_new_incident, dedup=decision, sms_contacts_notified=notified)


def sms_event_key(incident_id: int) -> str:
    return f"incident-created:{incident_id}"


def send_incident_notifications(db: Session, incident: Incident, sender_id: str) -> int:
    """Idempotent emergency-contact SMS for a newly created incident. Returns contacts handled."""
    profile = db.query(UserProfile).filter(UserProfile.sender_id == sender_id).first()
    if profile and profile.emergency_contacts:
        try:
            return notify_emergency_contacts(
                db,
                event_key=sms_event_key(incident.id),
                sender_name=profile.name,
                contacts=profile.emergency_contacts,
                incident_type=incident.incident_type,
                incident_id=incident.id,
            )
        except Exception:
            db.rollback()
            logging.getLogger("setu.incident").exception("SMS notification failed for incident %s", incident.id)
    return 0


def handle_sos_packet(db: Session, packet: PacketIn, ai_result: Optional[dict] = None) -> Incident:
    """Back-compat wrapper: returns only the Incident. Prefer process_sos_packet."""
    return process_sos_packet(db, packet, ai_result=ai_result).incident


def close_incident_by_emergency_id(db: Session, emergency_id: Optional[str]) -> Optional[Incident]:
    """
    Close every OPEN incident linked to an emergency packet carrying this
    emergency_id (via RawPacket.emergency_id -> incident_id). emergency_id is
    not sender-scoped in the frozen packet spec, so an authorized responder's
    termination resolves ALL incidents that share it -- a squatted or colliding
    emergency_id can therefore never leave the genuine incident open.

    Returns the first incident closed, or None if there was nothing to close
    (no such packet/incident, or already CLOSED: silent no-op, per project
    convention -- termination never errors).
    """
    if not emergency_id:
        return None

    originals = (
        db.query(RawPacket)
        .filter(RawPacket.emergency_id == emergency_id, RawPacket.type == "emergency",
                RawPacket.incident_id.isnot(None))
        .order_by(RawPacket.id.asc())
        .all()
    )

    closed_first: Optional[Incident] = None
    seen = set()
    for original_packet in originals:
        if original_packet.incident_id in seen:
            continue
        seen.add(original_packet.incident_id)
        incident = db.query(Incident).filter(Incident.id == original_packet.incident_id).first()
        if not incident or incident.status == IncidentStatus.CLOSED:
            continue
        incident.status = IncidentStatus.CLOSED
        incident.closed_at = datetime.now(timezone.utc)
        _log_incident_action(db, incident.id, AuditAction.CLOSED, packet_id=original_packet.packet_id, commit=False)
        closed_first = closed_first or incident

    db.commit()
    return closed_first


def resolve_incident_by_id(db: Session, incident_id: int, actor: Optional[str] = None) -> Optional[Incident]:
    """
    Dashboard-initiated resolve path (POST /incidents/{id}/resolve,
    API-key gated -- see app/routers/incidents.py) -- a PARALLEL path to
    close_incident_by_emergency_id above, not a replacement. The mesh
    termination path stays authoritative for real responders in the
    field (Ed25519-signed, checked against the responder registry); this
    exists because a private signing key can't live in a browser, so the
    dashboard trusts its existing API-key auth instead for this one
    administrative action.

    Returns None only if the incident doesn't exist (caller should 404).
    Idempotent otherwise -- resolving an already-CLOSED incident is a
    silent no-op that still returns the incident, matching
    close_incident_by_emergency_id's "termination never errors" convention.
    """
    incident = db.query(Incident).filter(Incident.id == incident_id).first()
    if not incident:
        return None
    if incident.status == IncidentStatus.CLOSED:
        return incident

    incident.status = IncidentStatus.CLOSED
    incident.closed_at = datetime.now(timezone.utc)

    _log_incident_action(
        db, incident.id, AuditAction.CLOSED,
        detail=f"Resolved via dashboard (session {actor or 'unknown'}; not a mesh termination)"[:250],
        commit=False,
    )

    db.commit()
    db.refresh(incident)
    # Block 2 fix: this `return` was missing, so the first resolve of an open incident
    # closed it in the DB but the router saw None and answered 404 "Incident not found".
    return incident


# --- Dashboard view (Block 2) -------------------------------------------------

def display_priority(ai_priority: Optional[float], sender_priority: Optional[str]) -> str:
    """
    The one place the "priority label" rule lives. AI assessment (1.0-5.0)
    wins when present; otherwise the reporter's declared priority; else Medium.
    Thresholds match what the dashboard used before this moved server-side.
    """
    if isinstance(ai_priority, (int, float)):
        if ai_priority >= 4.5:
            return "Critical"
        if ai_priority >= 3.5:
            return "High"
        if ai_priority >= 2.0:
            return "Medium"
        return "Low"
    mapping = {"low": "Low", "medium": "Medium", "high": "High", "critical": "Critical"}
    return mapping.get((sender_priority or "").lower(), "Medium")


def report_counts(db: Session, incident_ids: list[int]) -> dict[int, int]:
    """Emergency packets linked to each incident (>=1 report per incident)."""
    if not incident_ids:
        return {}
    from sqlalchemy import func
    rows = (
        db.query(RawPacket.incident_id, func.count(RawPacket.id))
        .filter(RawPacket.incident_id.in_(incident_ids), RawPacket.type == "emergency")
        .group_by(RawPacket.incident_id)
        .all()
    )
    return {incident_id: count for incident_id, count in rows}


def incident_view(incident: Incident, report_count: Optional[int] = None) -> dict:
    return {
        "id": incident.id,
        "incident_type": incident.incident_type,
        "latitude": incident.latitude,
        "longitude": incident.longitude,
        "status": incident.status.value if hasattr(incident.status, "value") else str(incident.status),
        "hop_count": incident.hop_count,
        "relay_path": incident.relay_path,
        "sender_priority": incident.sender_priority,
        "ai_incident_type": incident.ai_incident_type,
        "ai_incident_confidence": incident.ai_incident_confidence,
        "ai_incident_explanation": incident.ai_incident_explanation,
        "ai_urgency": incident.ai_urgency,
        "ai_urgency_confidence": incident.ai_urgency_confidence,
        "ai_urgency_explanation": incident.ai_urgency_explanation,
        "ai_priority": incident.ai_priority,
        "display_priority": display_priority(incident.ai_priority, incident.sender_priority),
        "report_count": max(report_count or 1, 1),
        "created_at": incident.created_at,
        "updated_at": incident.updated_at,
        "closed_at": incident.closed_at,
    }
