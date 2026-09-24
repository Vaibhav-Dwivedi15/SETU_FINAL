"""
Incident endpoints for the responder dashboard.

All routes here are responder-only, gated by the API-key check --
this is where profile data (name, age, medical history) can leak if
misconfigured, so every route in this file must keep the auth dependency.
"""

from typing import List

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.core.rate_limit import enforce_responder_action_rate_limit
from app.core.security import verify_responder_api_key
from app.db.base import get_db
from app.models.audit_log import IncidentAuditLog
from app.models.incident import Incident
from app.models.packet import RawPacket
from app.models.user_profile import UserProfile
from app.schemas.incident import IncidentOut, ProfileOut, AuditLogOut
from app.services.incident_service import incident_view, report_counts, resolve_incident_by_id

router = APIRouter()


@router.post("/incidents/{incident_id}/resolve", response_model=IncidentOut)
def resolve_incident(
    incident_id: int,
    db: Session = Depends(get_db),
    _: None = Depends(verify_responder_api_key),
    # SEP 2026: RESPONDER ACTION tier -- see responders.py's POST route
    # for the same reasoning. This is a state-changing administrative
    # action parallel to the mesh's own signed TerminationPacket path.
    _rate_limit: None = Depends(enforce_responder_action_rate_limit),
):
    """
    Dashboard "Mark Resolved" endpoint -- API-key gated (same X-API-Key
    header as every other route in this file), NOT signature-based. This
    is a PARALLEL administrative path alongside the mesh-native signed
    termination packet (POST /ingest, type=termination) -- it does not
    replace or touch that path. See incident_service.resolve_incident_by_id
    for why: a private Ed25519 signing key can't live in a browser, so
    the dashboard trusts the same API key it already uses for reads
    instead, for this one write action.

    Idempotent: resolving an already-CLOSED incident returns 200 with
    the incident unchanged, not an error -- matches the mesh termination
    path's "closing never errors" convention. Only 404s if the
    incident_id doesn't exist at all.
    """
    incident = resolve_incident_by_id(db, incident_id)
    if incident is None:
        raise HTTPException(status_code=404, detail="Incident not found.")
    return incident_view(incident, report_counts(db, [incident.id]).get(incident.id))


@router.get("/incidents", response_model=List[IncidentOut])
def list_incidents(
    db: Session = Depends(get_db),
    _: None = Depends(verify_responder_api_key),
):
    incidents = db.query(Incident).order_by(Incident.created_at.desc()).all()
    counts = report_counts(db, [i.id for i in incidents])
    return [incident_view(i, counts.get(i.id)) for i in incidents]


@router.get("/incidents/{incident_id}/profile", response_model=List[ProfileOut])
def get_incident_profiles(
    incident_id: int,
    db: Session = Depends(get_db),
    _: None = Depends(verify_responder_api_key),
):
    """
    Returns full sender profile(s) for everyone who reported this
    incident. Looks up which sender_ids are behind this incident's raw
    packets, then fetches their profiles -- profile data never travels
    through mesh packets, this is the only path to it.
    """
    incident = db.query(Incident).filter(Incident.id == incident_id).first()
    if not incident:
        raise HTTPException(status_code=404, detail="Incident not found.")

    sender_ids = (
        db.query(RawPacket.sender_id)
        .filter(RawPacket.incident_id == incident_id)
        .distinct()
        .all()
    )
    sender_ids = [s[0] for s in sender_ids]

    profiles = db.query(UserProfile).filter(
        UserProfile.sender_id.in_(sender_ids)
    ).all()

    return profiles


@router.get("/incidents/{incident_id}/history", response_model=List[AuditLogOut])
def get_incident_history(
    incident_id: int,
    db: Session = Depends(get_db),
    _: None = Depends(verify_responder_api_key),
):
    """
    Chronological audit trail for one incident -- every CREATE, MERGE,
    and CLOSE action, in order. Matches the "Incident Timeline" concept
    from project memory (First Report -> Second Report -> ... -> Resolved).
    """
    incident = db.query(Incident).filter(Incident.id == incident_id).first()
    if not incident:
        raise HTTPException(status_code=404, detail="Incident not found.")

    return (
        db.query(IncidentAuditLog)
        .filter(IncidentAuditLog.incident_id == incident_id)
        .order_by(IncidentAuditLog.created_at.asc())
        .all()
    )