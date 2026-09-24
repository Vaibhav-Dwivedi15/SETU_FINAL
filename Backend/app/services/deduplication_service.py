"""
Deduplication service.

Decides whether a new emergency packet belongs to an existing OPEN
incident, or should create a brand new one. Two emergency reports are
considered the same real-world incident if they're close in location,
same incident_type, and close in time.

These two constants are the only "judgment call" numbers here -- tune
them based on real testing, not fixed forever.

incident_type gap: the frozen mesh spec doesn't send incident_type on
EmergencyPacket (see app/schemas/packet.py docstring). When absent, this
falls back to classification_service.infer_incident_type() (same keyword
stopgap used at incident-creation time) so a packet's dedup lookup uses
the SAME type an un-typed packet would be classified/created as -- if
these two ever used different logic, corroborating reports could fail
to merge into the incident they just helped create.
"""

import math
from datetime import datetime, timedelta, timezone
from typing import Optional

from sqlalchemy.orm import Session

from app.models.incident import Incident, IncidentStatus
from app.schemas.packet import PacketIn
from app.services.classification_service import infer_incident_type

from app.core.contract import INCIDENT_DEDUP_RADIUS_METERS, INCIDENT_DEDUP_WINDOW_SECONDS

DEDUP_DISTANCE_METERS = INCIDENT_DEDUP_RADIUS_METERS
DEDUP_TIME_WINDOW_MINUTES = INCIDENT_DEDUP_WINDOW_SECONDS // 60

EARTH_RADIUS_METERS = 6371000


def haversine_distance_meters(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """
    Straight-line distance between two lat/lon points, in meters.
    Standard haversine formula -- accounts for Earth's curvature, which
    matters even at these small distances if you want accurate results.
    """
    phi1, phi2 = math.radians(lat1), math.radians(lat2)
    d_phi = math.radians(lat2 - lat1)
    d_lambda = math.radians(lon2 - lon1)

    a = (
        math.sin(d_phi / 2) ** 2
        + math.cos(phi1) * math.cos(phi2) * math.sin(d_lambda / 2) ** 2
    )
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))

    return EARTH_RADIUS_METERS * c


def resolve_incident_type(packet: PacketIn) -> str:
    """
    Single source of truth for 'what incident_type does this packet
    count as' -- used identically by dedup lookup AND incident creation,
    so the two can never disagree on a given packet's type.
    """
    incident_type = packet.incident_type if packet.incident_type else infer_incident_type(packet.message)
    return incident_type.value if hasattr(incident_type, "value") else incident_type


def find_matching_incident(db: Session, packet: PacketIn) -> Optional[Incident]:
    """
    Look for an existing OPEN incident that this emergency packet should
    be merged into. Only considers incidents of the same type -- distance
    and time are checked in Python since we need the haversine formula,
    not a simple SQL comparison.
    """
    incident_type = resolve_incident_type(packet)
    lat = packet.latitude if packet.latitude is not None else 0.0
    lon = packet.longitude if packet.longitude is not None else 0.0

    time_cutoff = datetime.now(timezone.utc) - timedelta(minutes=DEDUP_TIME_WINDOW_MINUTES)

    candidates = (
        db.query(Incident)
        .filter(
            Incident.incident_type == incident_type,
            Incident.status == IncidentStatus.OPEN,
            Incident.created_at >= time_cutoff,
        )
        .all()
    )

    for incident in candidates:
        distance = haversine_distance_meters(
            lat, lon,
            incident.latitude, incident.longitude,
        )
        if distance <= DEDUP_DISTANCE_METERS:
            return incident

    return None