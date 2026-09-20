"""
SETU AI - Incident Classification Engine

This module identifies the type of emergency
reported in an incoming message.

Author : SETU Team
Version : 2.0
""" 

import re
from typing import Dict, List

# ==========================
# Incident Types
# ==========================

FIRE = "Fire"
MEDICAL = "Medical"
ACCIDENT = "Accident"
FLOOD = "Flood"
BUILDING_COLLAPSE = "Building Collapse"
UNKNOWN = "Unknown"

# ==========================
# Incident Rule Database
# ==========================

INCIDENT_RULES = {
    FIRE: [
        "fire",
        "flames",
        "smoke",
        "burning",
        "blaze"
    ],

    MEDICAL: [
        "medical",
        "ambulance",
        "heart attack",
        "unconscious",
        "bleeding"
    ],

    ACCIDENT: [
        "accident",
        "crash",
        "collision",
        "vehicle",
        "truck",
        "bike"
    ],

    FLOOD: [
        "flood",
        "waterlogging",
        "overflow"
    ],

    BUILDING_COLLAPSE: [
        "collapse",
        "building collapse",
        "debris",
        "trapped"
    ]
}

# ==========================
# Helper Functions
# ==========================

def contains_keyword(message: str, keyword: str) -> bool:
    """
    Check whether a keyword exists
    as a complete word.
    """
    return re.search(rf"\b{re.escape(keyword)}\b", message) is not None


def normalize_message(message: str) -> str:
    """
    Normalize the incoming message.
    """
    return message.lower().strip()

# ==========================
# Incident Detection Engine
# ==========================

def detect_incident(message: str) -> str:
    """
    Detect the type of emergency incident
    from the incoming message.
    """

    message = normalize_message(message)

    for incident, keywords in INCIDENT_RULES.items():
        for word in keywords:
            if contains_keyword(message, word):
                return incident

    return UNKNOWN

# ==========================
# Local Testing
# ==========================

if __name__ == "__main__":
    print(detect_incident("Fire in my building"))
    print(detect_incident("Major accident on highway"))
    print(detect_incident("Medical emergency"))
    print(detect_incident("Flood water rising"))
    print(detect_incident("Building collapse"))
    print(detect_incident("Hello"))