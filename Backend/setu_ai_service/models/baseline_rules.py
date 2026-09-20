import re
"""
SETU AI - Emergency Severity Rule Engine

This module performs the first-stage urgency classification
for incoming emergency messages.

Author : SETU Team
Version : 2.0
"""

from typing import Dict, List

# Urgency Levels
CRITICAL = 5
HIGH = 4
MEDIUM = 3
LOW = 2
NORMAL = 1

CRITICAL_KEYWORDS = [
    # Fire
    "fire",
    "flames",
    "smoke",
    "burning",
    "blaze",

    # Accident
    "accident",
    "crash",
    "collision",
    "vehicle",
    "truck",
    "bike",

    # Medical
    "medical",
    "ambulance",
    "heart attack",
    "unconscious",
    "critical",

    # Natural Disaster
    "earthquake",
    "flood",
    "flooding",
    "overflowing",
    "underwater",
    "waterlogging",
    "overflow",

    # Building Collapse
    "collapse",
    "collapsed",
    "building collapse",
    "debris",
    "trapped",

    # --- Hinglish (Roman-script Hindi) equivalents ---
    # Fire
    "aag",
    "aag lag gayi",
    "jal raha",
    "dhuan",

    # Accident
    "durghatna",
    "takkar",

    # Medical
    "dil ka daura",
    "behosh",
    "khoon",
    "khoon nikal raha",

    # Natural Disaster
    "bhukamp",
    "baadh",
    "paani bhar gaya",

    # Building Collapse
    "malba",
    "phans gaya",
    "phas gayi",
    "imarat gir gayi",
    "chhat gir gayi",

    # --- Women's safety / stealth SOS (critical: matches the project's
    # demonstrated women's-safety vertical, not just disaster SOS) ---
    "bachao",
    "chhedchhad",
    "peecha kar raha",
    "pareshan kar raha",
    "molest",
    "molesting",
    "stalking",
    "harassment",
    "harassing",
    "harassed",
    "unsafe",
    "asurakshit",
    "following me",
    "wont leave me alone",
    "staring at me",
    "touching me",
    "grabbing me",
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
]


HIGH_KEYWORDS = [
    "help",
    "injured",
    "bleeding",
    "wound",
    "pain",
    "emergency",
    "rescue",
    "save",

    # Hinglish
    "madad",
    "zakhmi",
    "chot lagi",
    "dard ho raha",
]

MEDIUM_KEYWORDS = [
    "assistance",
    "support",
    "need help",
    "stuck",

    # Hinglish
    "sahayata",
    "phasa hua",
]

LOW_KEYWORDS = [
    "guide",
    "information",
    "directions",
    "query",

    # Hinglish
    "jaankari",
    "raasta",
    "disha nirdesh",
]

# Urgency Rule Database
URGENCY_RULES = {
    CRITICAL: CRITICAL_KEYWORDS,
    HIGH: HIGH_KEYWORDS,
    MEDIUM: MEDIUM_KEYWORDS,
    LOW: LOW_KEYWORDS
}

def normalize_message(message: str) -> str:
    """
    Normalize incoming message before processing.
    """
    return message.lower().strip()

def contains_keyword(message: str, keyword: str) -> bool:
    """
    Check whether a keyword exists as a complete word
    inside the message.
    """
    return re.search(rf"\b{re.escape(keyword)}\b", message) is not None

def classify_message(message: str) -> int:
    """
    Classify an emergency message and return its urgency level.
    """
    message = normalize_message(message)

    for urgency, keywords in URGENCY_RULES.items():
     for word in keywords:
        if contains_keyword(message, word):
            return urgency

    return NORMAL


if __name__ == "__main__":
    test_messages = [
        "Fire in my building",
        "Major accident on highway",
        "Medical emergency at railway station",
        "Help me please",
        "Hello"
    ]

    for message in test_messages:
        print(f"Message: {message}")
        print(f"Urgency: {classify_message(message)}")
        print("-" * 30)
