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
    "waterlogging",
    "overflow",

    # Building Collapse
    "collapse",
    "building collapse",
    "debris",
    "trapped"
]


HIGH_KEYWORDS = [
    "help",
    "injured",
    "bleeding",
    "wound",
    "pain",
    "emergency",
    "rescue",
    "save"
]

MEDIUM_KEYWORDS = [
    "assistance",
    "support",
    "need help",
    "stuck"
]

LOW_KEYWORDS = [
    "guide",
    "information",
    "directions",
    "query"
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