"""
SETU AI - Incident Classification Engine
Classifies incoming emergency messages into 10 key disaster categories with root-hazard precedence.
"""

import re
from typing import Dict, List

# ==========================
# 10 Incident Types (Per Specification)
# ==========================
EARTHQUAKE = "Earthquake"
CYCLONE = "Cyclone"
LANDSLIDE = "Landslide"
FLOOD = "Flood"
BUILDING_COLLAPSE = "Building Collapse"
FIRE = "Fire"
ROAD_BLOCKAGE = "Road Blockage"
MISSING_PERSON = "Missing Person"
RESOURCE_SHORTAGE = "Resource Shortage"
MEDICAL = "Medical Emergency"
UNKNOWN = "Unknown"

# ==========================
# Keyword Rule Database (Root Hazards first, then consequences)
# ==========================
INCIDENT_RULES: Dict[str, List[str]] = {
    EARTHQUAKE: [
        "earthquake", "tremor", "aftershock", "quake", "ground shaking"
    ],
    CYCLONE: [
        "cyclone", "hurricane", "typhoon", "tornado", "gale", "high winds"
    ],
    LANDSLIDE: [
        "landslide", "mudslide", "rockfall", "debris flow", "hill collapse"
    ],
    FLOOD: [
        "flood", "waterlogging", "water rising", "submerged", "drowning", "inundated", "overflow"
    ],
    BUILDING_COLLAPSE: [
        "building collapse", "collapse", "debris", "trapped under", "rubble", "crushed"
    ],
    FIRE: [
        "fire", "flames", "smoke", "burning", "blaze", "cylinder blast", "explosion"
    ],
    ROAD_BLOCKAGE: [
        "road blocked", "bridge collapsed", "tree fallen", "blocked path", "no access", "highway blocked"
    ],
    MISSING_PERSON: [
        "missing", "lost child", "cannot find", "separated", "untraceable", "last seen"
    ],
    RESOURCE_SHORTAGE: [
        "food shortage", "no water", "drinking water", "starving", "rations", "blankets", "need food", "dry ration"
    ],
    MEDICAL: [
        "medical", "ambulance", "heart attack", "unconscious", "bleeding", "injured",
        "injury", "fracture", "oxygen", "breathing difficulty", "snake bite", "pregnant"
    ],
}


def normalize_message(message: str) -> str:
    return message.lower().strip()


def contains_keyword(message: str, keyword: str) -> bool:
    return re.search(rf"\b{re.escape(keyword)}\b", message) is not None


def detect_incident(message: str) -> str:
    normalized = normalize_message(message)

    # Check root hazards first, multi-word keywords before single words
    for incident, keywords in INCIDENT_RULES.items():
        for keyword in sorted(keywords, key=len, reverse=True):
            if contains_keyword(normalized, keyword):
                return incident

    return UNKNOWN
