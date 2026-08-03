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
EARTHQUAKE = "Earthquake"
WOMEN_SAFETY = "Women Safety"
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
        "blaze",
        # Hinglish
        "aag",
        "aag lag gayi",
        "jal raha",
        "dhuan",
    ],

    MEDICAL: [
        "medical",
        "ambulance",
        "heart attack",
        "unconscious",
        "bleeding",
        # Hinglish
        "dil ka daura",
        "behosh",
        "khoon",
        "khoon nikal raha",
    ],

    ACCIDENT: [
        "accident",
        "crash",
        "collision",
        "vehicle",
        "truck",
        "bike",
        # Hinglish
        "durghatna",
        "takkar",
    ],

    FLOOD: [
        "flood",
        "flooding",
        "overflowing",
        "underwater",
        "waterlogging",
        "overflow",
        # Hinglish
        "baadh",
        "paani bhar gaya",
    ],

    BUILDING_COLLAPSE: [
        "collapse",
        "collapsed",
        "building collapse",
        "debris",
        "trapped",
        # Hinglish
        "malba",
        "phans gaya",
        "phas gayi",
        "imarat gir gayi",
        "chhat gir gayi",
    ],

    EARTHQUAKE: [
        "earthquake",
        # Hinglish
        "bhukamp",
    ],

    WOMEN_SAFETY: [
        "harassment",
        "harassing",
        "harassed",
        "molest",
        "molesting",
        "stalking",
        "unsafe",
        "asurakshit",
        "following me",
        "wont leave me alone",
        "staring at me",
        "touching me",
        "grabbing me",
        # Hinglish
        "bachao",
        "chhedchhad",
        "peecha kar raha",
        "pareshan kar raha",
        "ghoor raha",
        "ghoor rahe",
        "chhed raha",
        "chhoo raha",
        "haath laga raha",
        "tang kar raha",
        "zabardasti",
        "gandi nazar",
        "peeche aa raha",
        "kidnap kar",
        "utha ke le ja raha",
        "follow kar raha",
        "picha kar raha hai",
        "ajeeb tarike se dekh raha",
        "fabti kas raha",
        "comment kas raha",
        "seeti baja raha",
        "gande comment kar raha",
        "khinch ke le ja raha",
        "dhamki",
        "mujhe nuksan pahunchane ki koshish",
        "ghere mein le liya",
        "rasta rok liya",
        "corner kar diya",
        "chaaron taraf se ghera",
        "blocking my way",
        "threatening me",
        "trying to hurt me",
        "cornered me",
    ],
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
