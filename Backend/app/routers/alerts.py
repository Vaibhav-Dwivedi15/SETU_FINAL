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

from fastapi import APIRouter, Depends, HTTPException, Query, Request
from sqlalchemy.orm import Session

from app.core.rate_limit import (
    enforce_public_write_rate_limit,
    nearby_ip_limiter,
    nearby_sender_limiter,
)
from app.core.security import verify_responder_api_key
from app.db.base import get_db
from app.models.incident import Incident
from app.models.user_profile import UserProfile
from app.services.request_auth import (
    SignedHeaders,
    require_signed_body,
    signed_headers,
    verify_signed_request,
)
from app.schemas.alert import NearbyIncidentOut, RespondIn, CommunityResponseOut
from app.services.nearby_alert_service import (
    get_nearby_open_incidents,
    record_response,
    DEFAULT_RADIUS_KM,
    MAX_RADIUS_KM,
)
from app.models.community_response import CommunityResponse

router = APIRouter()


def _require_registered(db: Session, sender_id: str) -> None:
    if not db.query(UserProfile.id).filter(UserProfile.sender_id == sender_id).first():
        raise HTTPException(status_code=403, detail="Register your profile before using community alerts.")


@router.get("/alerts/nearby", response_model=List[NearbyIncidentOut])
def nearby_alerts(
    request: Request,
    lat: float = Query(..., ge=-90, le=90),
    lon: float = Query(..., ge=-180, le=180),
    radius_km: float = Query(DEFAULT_RADIUS_KM, gt=0, le=MAX_RADIUS_KM),
    sender_id: str = Query(None, description="Optional; if present must equal the authenticated key."),
    db: Session = Depends(get_db),
    headers: SignedHeaders = Depends(signed_headers),
):
    """
    Polling endpoint: the mobile app supplies its OWN current location on each
    call -- nothing is stored server-side. Returns privacy-safe OPEN-incident
    summaries only, nearest first.

    AUTHORIZATION (Block 2): the request must be signed by a REGISTERED SETU
    device key (services/request_auth.py; parts = [lat, lon, radius_km] as the
    raw query strings), and is rate limited per IP and per key. Anonymous
    callers can no longer enumerate incidents. Results are the minimum the app
    needs: no coordinates, no reporter identity, distance rounded to 100 m,
    at most MAX_NEARBY_RESULTS rows.
    """
    nearby_ip_limiter.check(request)
    signer = verify_signed_request(
        db, headers, "GET", request.url.path,
        [request.query_params.get("lat", ""), request.query_params.get("lon", ""),
         request.query_params.get("radius_km", "")],
    )
    nearby_sender_limiter.check(request, key=signer)
    if sender_id is not None and sender_id != signer:
        raise HTTPException(status_code=403, detail="sender_id does not match the authenticated key.")
    _require_registered(db, signer)

    return get_nearby_open_incidents(db, lat=lat, lon=lon, radius_km=radius_km, exclude_sender_id=signer)


@router.post("/alerts/{incident_id}/respond", response_model=CommunityResponseOut)
def respond_to_alert(
    incident_id: int,
    payload: RespondIn,
    db: Session = Depends(get_db),
    # PUBLIC-WRITE tier (lenient) -- see core/rate_limit.py.
    _rate_limit: None = Depends(enforce_public_write_rate_limit),
    signer: str = Depends(require_signed_body),
):
    """
    Records/updates a community member's response action for an incident.
    Upsert by (incident_id, sender_id). Block 2: the request must be signed by
    the key it claims to respond as (no more free-text sender_id), and that key
    must be a registered profile.
    """
    if payload.sender_id != signer:
        raise HTTPException(status_code=403, detail="sender_id does not match the authenticated key.")
    _require_registered(db, signer)

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
