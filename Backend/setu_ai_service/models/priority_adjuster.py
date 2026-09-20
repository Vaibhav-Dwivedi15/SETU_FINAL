"""
SETU AI - Dynamic Priority Adjustment Engine

This module dynamically adjusts the emergency
priority based on real-world conditions.

Author : SETU Team
Version : 2.0
"""

from typing import Final

# ==========================
# Configuration
# ==========================

MAX_PRIORITY: Final[float] = 5.0
MIN_PRIORITY: Final[float] = 1.0

RELAY_PENALTY: Final[float] = 0.2
MESSAGE_AGE_PENALTY: Final[float] = 0.3

MAX_RELAY_COUNT: Final[int] = 5
MAX_MESSAGE_AGE: Final[int] = 120

# ==========================
# Incident Priority Boost
# ==========================

INCIDENT_PRIORITY_BOOST = {
    "Fire": 0.30,
    "Medical": 0.20,
    "Accident": 0.20,
    "Flood": 0.40,
    "Building Collapse": 0.50,
    "Earthquake": 0.45,
    "Women Safety": 0.45,
    "Unknown": 0.00,
}

"""
Adjust emergency priority using
multiple real-world factors.

Factors:
- Base priority
- Relay count
- Message age
- Incident type
"""

def adjust_priority(
    base_priority: float,
    relay_count: int,
    age_seconds: int,
    incident_type: str = "Unknown"
) -> float:
    
    if base_priority < MIN_PRIORITY:
        base_priority = MIN_PRIORITY

    if base_priority > MAX_PRIORITY:
        base_priority = MAX_PRIORITY

    priority = float(base_priority)
    priority += INCIDENT_PRIORITY_BOOST.get(incident_type, 0.0)

    if relay_count > MAX_RELAY_COUNT:
        priority -= RELAY_PENALTY

    if age_seconds > MAX_MESSAGE_AGE:
        priority -= MESSAGE_AGE_PENALTY
      

    priority = max(MIN_PRIORITY, min(priority, MAX_PRIORITY))

    return round(priority, 2)


if __name__ == "__main__":
    print(adjust_priority(5, 1, 20, "Fire"))
    print(adjust_priority(5, 6, 180, "Medical"))
    print(adjust_priority(4, 2, 30, "Building Collapse"))
    print(adjust_priority(4, 1, 10, "Women Safety"))
    print(adjust_priority(4, 1, 10, "Earthquake"))
