"""
SETU AI - Incident Classification Engine
Classifies incoming emergency messages into 10 key disaster categories.
"""

import re
from typing import Dict, List

# ==========================
# 10 Incident Types (Per Specification)
# ==========================
FLOOD = "Flood"
EARTHQUAKE = "Earthquake"
FIRE = "Fire"
LANDSLIDE = "Landslide"
CYCLONE = "Cyclone"
BUILDING_COLLAPSE = "Building Collapse"
ROAD_BLOCKAGE = "Road Blockage"
MEDICAL = "Medical Emergency"
MISSING_PERSON = "Missing Person"
RESOURCE_SHORTAGE = "Resource Shortage"
UNKNOWN = "Unknown"

# ==========================
# Keyword Rule Database
# ==========================
INCIDENT_RULES: Dict[str, List[str]] = {
    FIRE: [
        "fire", "flames", "smoke", "burning", "blaze", "cylinder blast", "explosion"
    ],
    MEDICAL: [
        "medical", "ambulance", "heart attack", "unconscious", "bleeding", "injured",
        "injury", "fracture", "oxygen", "breathing difficulty", "snake bite", "pregnant"
    ],
    FLOOD: [
        "flood", "waterlogging", "water rising", "submerged", "drowning", "inundated", "overflow"
    ],
    BUILDING_COLLAPSE: [
        "collapse", "building collapse", "debris", "trapped under", "rubble", "crushed"
    ],
    EARTHQUAKE: [
        "earthquake", "tremor", "aftershock", "quake", "shakes", "ground shaking"
    ],
    LANDSLIDE: [
        "landslide", "mudslide", "rockfall", "debris flow", "hill collapse"
    ],
    CYCLONE: [
        "cyclone", "hurricane", "typhoon", "storm", "high winds", "tornado", "gale"
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
}


def normalize_message(message: str) -> str:
    return message.lower().strip()


def contains_keyword(message: str, keyword: str) -> bool:
    return re.search(rf"\b{re.escape(keyword)}\b", message) is not None


def detect_incident(message: str) -> str:
    normalized = normalize_message(message)

    # Check multi-word keywords first, then single words
    for incident, keywords in INCIDENT_RULES.items():
        for keyword in sorted(keywords, key=len, reverse=True):
            if contains_keyword(normalized, keyword):
                return incident

    return UNKNOWN
