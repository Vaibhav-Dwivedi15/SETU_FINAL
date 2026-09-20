"""
Community alert + response-action endpoints -- Phase 3.

GET /alerts/nearby and POST /alerts/{incident_id}/respond are PUBLIC
(no X-API-Key) -- these are called by ordinary SETU users' mobile apps,
not responders/dashboard, so they intentionally do NOT use
verify_responder_api_key (that gate is for profile/audit data, which
these routes never touch or return -- see nearby_alert_service.py's
privacy notes).

GET /alerts/{incident_id}/responses IS responder-gated -- it's a
dashboard-facing view of who's responding to a given incident, matching
the "incident detail view: relay/delivery/notification status" spec
item for Phase 4's dashboard redesign to eventually surface.

See nearby_alert_service.py's module docstring for the polling-vs-push
architecture assumption -- confirm with Sudheer's mobile team before
treating this as "real-time notification."
"""
from typing import List

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session

from app.core.security import verify_responder_api_key
from app.db.base import get_db
from app.models.incident import Incident
from app.schemas.alert import NearbyIncidentOut, RespondIn, CommunityResponseOut
from app.services.nearby_alert_service import (
    get_nearby_open_incidents,
    record_response,
    DEFAULT_RADIUS_KM,
    MAX_RADIUS_KM,
)
from app.models.community_response import CommunityResponse

router = APIRouter()


@router.get("/alerts/nearby", response_model=List[NearbyIncidentOut])
def nearby_alerts(
    lat: float = Query(..., ge=-90, le=90),
    lon: float = Query(..., ge=-180, le=180),
    radius_km: float = Query(DEFAULT_RADIUS_KM, gt=0, le=MAX_RADIUS_KM),
    sender_id: str = Query(None, description="Excludes incidents this sender already responded to, if given."),
    db: Session = Depends(get_db),
):
    """
    Polling endpoint: mobile app supplies its OWN current location on
    each call (app open / periodic poll) -- nothing is stored server-side.
    Returns privacy-safe OPEN-incident summaries only, nearest first.
    """
    return get_nearby_open_incidents(db, lat=lat, lon=lon, radius_km=radius_km, exclude_sender_id=sender_id)


@router.post("/alerts/{incident_id}/respond", response_model=CommunityResponseOut)
def respond_to_alert(
    incident_id: int,
    payload: RespondIn,
    db: Session = Depends(get_db),
):
    """
    Records/updates a community member's response action for an
    incident. Upsert by (incident_id, sender_id) -- see
    nearby_alert_service.record_response for why a resend updates
    in place instead of duplicating.
    """
    incident = db.query(Incident).filter(Incident.id == incident_id).first()
    if not incident:
        raise HTTPException(status_code=404, detail="Incident not found.")

    return record_response(db, incident_id=incident_id, sender_id=payload.sender_id, response_type=payload.response_type)


@router.get("/incidents/{incident_id}/responses", response_model=List[CommunityResponseOut])
def get_incident_responses(
    incident_id: int,
    db: Session = Depends(get_db),
    _: None = Depends(verify_responder_api_key),
):
    """
    Responder-dashboard-facing: every community response recorded
    against this incident, most recent first. Grouped under the same
    /incidents/{id}/... URL family as history/profile (app/routers/incidents.py)
    for consistency, even though it lives in this router file.
    """
    incident = db.query(Incident).filter(Incident.id == incident_id).first()
    if not incident:
        raise HTTPException(status_code=404, detail="Incident not found.")

    return (
        db.query(CommunityResponse)
        .filter(CommunityResponse.incident_id == incident_id)
        .order_by(CommunityResponse.updated_at.desc())
        .all()
    )
