"""
Lightweight incident_type inference from packet.message.

The frozen packet spec doesn't carry incident_type on EmergencyPacket
(only message + priority) -- see incident_service.py's docstring. Without
SOME type inference, every incident defaults to OTHER, which breaks
deduplication's incident_type filter: a fire and a flood at the same
spot would wrongly merge into one incident.

This is a stopgap keyword pass, not real classification. When Vaishnavi's
AI triage is ready, it should replace/override this -- swap the call in
incident_service.py, nothing else needs to change.
"""

from app.schemas.packet import IncidentType

_KEYWORDS = {
    IncidentType.FIRE: ["fire", "burn", "smoke", "flame"],
    IncidentType.FLOOD: ["flood", "water rising", "drowning", "river"],
    IncidentType.MEDICAL: ["medical", "injured", "unconscious", "bleeding", "heart attack"],
    IncidentType.TRAPPED: ["trapped", "stuck", "collapsed on me", "can't move"],
    IncidentType.STRUCTURAL_COLLAPSE: ["collapse", "building fell", "rubble", "structure"],
    IncidentType.LANDSLIDE: ["landslide", "mudslide", "slope"],
    IncidentType.STAMPEDE: ["stampede", "crowd crush", "trampled"],
}


def infer_incident_type(message: str) -> IncidentType:
    if not message:
        return IncidentType.OTHER

    lowered = message.lower()
    for incident_type, keywords in _KEYWORDS.items():
        if any(kw in lowered for kw in keywords):
            return incident_type

    return IncidentType.OTHER