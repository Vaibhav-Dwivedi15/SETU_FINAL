"""
Nearby community alert service -- Phase 3.

ARCHITECTURE NOTE (design assumption, flag with team/Sudheer before
demoing as "notification"): this is a POLLING design, not push. No FCM
(Firebase Cloud Messaging) or any push-notification infra exists
anywhere in this stack today, and UserProfile has no stored location
(by design -- storing continuous user location would be a real privacy
cost). Instead: the mobile app supplies its OWN current lat/lon on
demand (app open / periodic poll) to GET /alerts/nearby, and the backend
filters currently-OPEN incidents within radius of THAT submitted point.
No location is stored anywhere -- it exists only for the duration of one
request. If a real push experience is wanted later, that's a genuinely
separate FCM integration (device token registration, etc.), not a small
change to this file.

PRIVACY: get_nearby_open_incidents() below returns ONLY incident-level,
non-identifying fields (type, distance, priority, created_at). It NEVER
joins to UserProfile or RawPacket.sender_id for the reporting victim --
see the project spec's required message text ("An emergency has been
reported near your area...", no identity). Community responders' own
sender_id IS stored (in CommunityResponse), but that's the responder's
own identity attached to their own action, not the victim's.

DISTANCE CALC: plain-Python haversine, mirrors the same formula/approach
setu_ai_service's geo-dedup already uses (500m radius dedup) -- kept as
an independent, self-contained implementation here rather than importing
across the vendored-AI-service boundary, so this feature's correctness
never depends on that import shim (see
app/utils/setu_ai_import_guard.py) or the AI service being reachable.
The incident set queried here is always small (only OPEN incidents),
so doing the distance filter in Python instead of a DB-side geo query
is not a real performance concern at this scale.
"""
import math
from typing import List, Optional
from datetime import datetime, timezone

from sqlalchemy.orm import Session

from app.models.incident import Incident, IncidentStatus
from app.models.community_response import CommunityResponse, ResponseType

EARTH_RADIUS_KM = 6371.0
DEFAULT_RADIUS_KM = 2.0
MAX_RADIUS_KM = 15.0  # hard cap so a bad client value can't force a huge scan/response
MAX_NEARBY_RESULTS = 20  # bounds the response (Block 2)
DISTANCE_ROUND_KM = 1  # decimals: distance reported to 100 m -- limits location triangulation


def haversine_km(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    lat1_r, lon1_r, lat2_r, lon2_r = map(math.radians, [lat1, lon1, lat2, lon2])
    dlat = lat2_r - lat1_r
    dlon = lon2_r - lon1_r
    a = math.sin(dlat / 2) ** 2 + math.cos(lat1_r) * math.cos(lat2_r) * math.sin(dlon / 2) ** 2
    c = 2 * math.asin(math.sqrt(a))
    return EARTH_RADIUS_KM * c


def get_nearby_open_incidents(
    db: Session,
    lat: float,
    lon: float,
    radius_km: float = DEFAULT_RADIUS_KM,
    exclude_sender_id: Optional[str] = None,
) -> List[dict]:
    """
    Returns OPEN incidents within radius_km of (lat, lon), sorted
    nearest-first. Each result is a plain dict of privacy-safe fields
    only -- never the reporting sender's identity or profile.

    exclude_sender_id: if given, incidents this sender_id has already
    recorded a CommunityResponse for are left out, so a client doesn't
    keep re-surfacing an alert the user already acted on. This is NOT
    "incidents this person reported" -- reporters aren't shown their own
    incident here in the current version either way, since (0.0, 0.0)
    GPS-unavailable fallback coordinates would otherwise make a reporter
    with no GPS match distance calculations unpredictably; that edge case
    is left as a known limitation, not silently special-cased.
    """
    radius_km = min(radius_km, MAX_RADIUS_KM)

    open_incidents = db.query(Incident).filter(Incident.status == IncidentStatus.OPEN).all()

    already_responded_ids = set()
    if exclude_sender_id:
        already_responded_ids = {
            row.incident_id
            for row in db.query(CommunityResponse.incident_id)
            .filter(CommunityResponse.sender_id == exclude_sender_id)
            .all()
        }

    results = []
    for incident in open_incidents:
        if incident.id in already_responded_ids:
            continue

        distance_km = haversine_km(lat, lon, incident.latitude, incident.longitude)
        if distance_km > radius_km:
            continue

        results.append({
            "incident_id": incident.id,
            "incident_type": incident.incident_type,
            "sender_priority": incident.sender_priority,
            "ai_priority": incident.ai_priority,
            "distance_km": round(distance_km, DISTANCE_ROUND_KM),
            "created_at": incident.created_at,
            "message": (
                "An emergency has been reported near your area. "
                "If you are safe and able to help, please open SETU for details."
            ),
        })

    results.sort(key=lambda r: r["distance_km"])
    return results[:MAX_NEARBY_RESULTS]


def record_response(
    db: Session,
    incident_id: int,
    sender_id: str,
    response_type: ResponseType,
) -> CommunityResponse:
    """
    Upsert: one row per (incident_id, sender_id). If this sender already
    responded to this incident, updates the response_type + updated_at
    in place (e.g. "I'm nearby" -> later "Already responding") rather
    than creating a second row -- see CommunityResponse model docstring.
    """
    existing = (
        db.query(CommunityResponse)
        .filter(
            CommunityResponse.incident_id == incident_id,
            CommunityResponse.sender_id == sender_id,
        )
        .first()
    )

    if existing:
        existing.response_type = response_type
        db.commit()
        db.refresh(existing)
        return existing

    entry = CommunityResponse(
        incident_id=incident_id,
        sender_id=sender_id,
        response_type=response_type,
    )
    db.add(entry)
    db.commit()
    db.refresh(entry)
    return entry
