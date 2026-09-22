"""
SETU AI - Dynamic Priority Adjustment Engine
Calculates numeric score and maps to bounded disaster tiers: CRITICAL, HIGH, MEDIUM, LOW.
"""

from typing import Final, Dict

MAX_PRIORITY: Final[float] = 5.0
MIN_PRIORITY: Final[float] = 1.0

RELAY_PENALTY: Final[float] = 0.2
MESSAGE_AGE_PENALTY: Final[float] = 0.3

MAX_RELAY_COUNT: Final[int] = 5
MAX_MESSAGE_AGE: Final[int] = 120

# All 10 Incident Category Priority Boosts
INCIDENT_PRIORITY_BOOST: Dict[str, float] = {
    "Building Collapse": 0.50,
    "Earthquake": 0.50,
    "Flood": 0.40,
    "Landslide": 0.40,
    "Cyclone": 0.40,
    "Medical Emergency": 0.40,
    "Fire": 0.30,
    "Missing Person": 0.30,
    "Road Blockage": 0.20,
    "Resource Shortage": 0.20,
    "Unknown": 0.00,
}


def adjust_priority(
    base_priority: float,
    relay_count: int,
    age_seconds: int,
    incident_type: str = "Unknown",
) -> float:
    base = max(MIN_PRIORITY, min(float(base_priority), MAX_PRIORITY))
    priority = base + INCIDENT_PRIORITY_BOOST.get(incident_type, 0.0)

    if relay_count > MAX_RELAY_COUNT:
        priority -= RELAY_PENALTY

    if age_seconds > MAX_MESSAGE_AGE:
        priority -= MESSAGE_AGE_PENALTY

    return round(max(MIN_PRIORITY, min(priority, MAX_PRIORITY)), 2)


def get_priority_tier(score: float) -> str:
    """Bounded priority tier mapping per specification."""
    if score >= 4.5:
        return "CRITICAL"
    elif score >= 3.5:
        return "HIGH"
    elif score >= 2.5:
        return "MEDIUM"
    return "LOW"
