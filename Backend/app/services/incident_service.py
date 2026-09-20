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

from typing import Optional
from datetime import datetime, timezone
from sqlalchemy import text
import zlib
from sqlalchemy.orm import Session

from app.models.audit_log import IncidentAuditLog, AuditAction
from app.models.incident import Incident, IncidentStatus
from app.models.packet import RawPacket
from app.models.user_profile import UserProfile
from app.schemas.packet import PacketIn, IncidentType
from app.services.classification_service import infer_incident_type
from app.services.deduplication_service import find_matching_incident
from app.services.sms_service import notify_emergency_contacts
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


def handle_sos_packet(db: Session, packet: PacketIn, ai_result: Optional[dict] = None) -> Incident:
    """
    Attach to an existing incident if one matches, else create new.
    Also links the already-stored RawPacket row to the resulting
    incident, via RawPacket.incident_id -- this is what makes closing
    an incident later an exact lookup instead of a location-based guess.

    ai_result is used for BOTH dedup and incident enrichment as of the
    reversed decision (see app/services/ai_analysis_service.py module
    docstring for full history/reasoning): the AI service's
    is_duplicate/matched_cluster_id is now the primary source of truth
    for new-vs-merge, NOT this backend's own find_matching_incident().
    find_matching_incident() is kept only as a FALLBACK for when
    ai_result is None (AI call failed/unavailable) -- never blend the
    two for a single packet; it's always one or the other, never both.

    SMS notification fires ONLY when a brand-new incident is created
    (existing is None) -- never on a merge into an existing incident,
    since that would spam the same contacts once per corroborating report.
    The government notification adapter call (Phase 2) follows the exact
    same rule, for the exact same reason.

    RACE CONDITION FIX (load test, Aug 2): a Postgres advisory transaction
    lock, scoped per incident_type, serializes the check+create section
    below so concurrent same-type packets can't each create their own
    incident. FOLLOW-UP FIX (same day): SMS notification was originally
    sent BEFORE commit, meaning it ran while the lock was still held --
    a slow network call inside a lock meant every other same-type packet
    queued behind that one HTTP request, causing timeouts under load.
    Moved SMS to after commit/lock-release: the lock now only covers
    fast DB work, and a slow SMS send only blocks its OWN request, not
    everyone else's. The government adapter call (Phase 2) follows after
    SMS, same reasoning -- it never runs while the lock is held.

    DIALECT GUARD (Aug, found via local pytest run): pg_advisory_xact_lock
    is Postgres-only -- SQLite (used by the test suite's in-memory DB,
    see tests/test_ingest.py) has no such function and raises
    OperationalError. Gated behind a dialect check so real deployments
    (Neon/Postgres) keep the actual concurrency protection, while local
    tests on SQLite skip the lock harmlessly. This does mean the race
    condition this lock exists to prevent is UNTESTED on SQLite -- the
    concurrent-load scenario this fixes was only ever verified against
    real Postgres (see load test notes, Aug 2), not reproducible in the
    local suite.
    """
    incident_type_for_lock = (
        packet.incident_type.value if packet.incident_type
        else infer_incident_type(packet.message).value
    )
    lock_key = zlib.crc32(incident_type_for_lock.encode())
    if db.get_bind().dialect.name == "postgresql":
        db.execute(text("SELECT pg_advisory_xact_lock(:key)"), {"key": lock_key})

    if ai_result is not None:
        # AI-driven dedup path (source of truth as of the reversed decision).
        # matched_cluster_id is an emergency_id (per setu_ai_service's own
        # handoff doc), not an incident id -- resolve it via the lookup
        # helper above. is_duplicate=False means this packet IS its own
        # new cluster (matched_cluster_id points to itself in that case),
        # so existing stays None and a new incident gets created below.
        existing = (
            _find_incident_by_emergency_id(db, ai_result["matched_cluster_id"])
            if ai_result.get("is_duplicate") and ai_result.get("matched_cluster_id")
            else None
        )
    else:
        # FALLBACK ONLY: AI call failed/unavailable this request. Falls
        # back to this backend's own DB-backed dedup rather than treating
        # every packet as new (which would spam duplicate incidents for
        # the whole duration of an AI outage).
        existing = find_matching_incident(db, packet)

    is_new_incident = existing is None
    incident = existing if existing else create_incident_from_packet(db, packet, ai_result=ai_result)

    raw = db.query(RawPacket).filter(RawPacket.packet_id == packet.packet_id).first()
    if raw:
        raw.incident_id = incident.id

    if is_new_incident:
        _log_incident_action(db, incident.id, AuditAction.CREATED, packet_id=packet.packet_id, commit=False)
    else:
        _log_incident_action(db, incident.id, AuditAction.MERGED, packet_id=packet.packet_id, commit=False)

    db.commit()  # releases the advisory lock here -- next same-type request can proceed now

    # SMS and the government notification adapter both happen AFTER
    # commit/lock-release -- a slow send only delays this one request's
    # response, not every other packet waiting on the lock. Both fire
    # only for genuinely new incidents, never on a merge.
    if is_new_incident:
        profile = db.query(UserProfile).filter(
            UserProfile.sender_id == packet.sender_id
        ).first()

        if profile and profile.emergency_contacts:
            notify_emergency_contacts(
                sender_name=profile.name,
                contacts=profile.emergency_contacts,
                incident_type=incident.incident_type,
                incident_id=incident.id,
            )

        # Phase 2: mock government notification adapter. Never blocking,
        # never able to affect the response below -- see
        # government_notification_service.notify_government's docstring.
        notify_government(db, incident)

    return incident


def close_incident_by_emergency_id(db: Session, emergency_id: Optional[str]) -> Optional[Incident]:
    """
    Find the incident linked to the emergency packet that this
    termination references (via RawPacket.emergency_id -> incident_id),
    and close it. Returns None if no such packet/incident exists, or the
    incident is already CLOSED (silent no-op, per project convention --
    termination never errors).
    """
    if not emergency_id:
        return None

    original_packet = (
        db.query(RawPacket)
        .filter(RawPacket.emergency_id == emergency_id, RawPacket.type == "emergency")
        .first()
    )
    if not original_packet or not original_packet.incident_id:
        return None

    incident = db.query(Incident).filter(Incident.id == original_packet.incident_id).first()
    if not incident or incident.status == IncidentStatus.CLOSED:
        return None

    incident.status = IncidentStatus.CLOSED
    incident.closed_at = datetime.now(timezone.utc)

    _log_incident_action(db, incident.id, AuditAction.CLOSED, packet_id=original_packet.packet_id, commit=False)

    db.commit()
    return incident


def resolve_incident_by_id(db: Session, incident_id: int) -> Optional[Incident]:
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
        detail="Resolved via dashboard (API-key auth, not mesh termination)",
        commit=False,
    )

    db.commit()
    db.refresh(incident)
