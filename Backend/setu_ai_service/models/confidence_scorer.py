"""
SETU AI - Confidence Scoring Engine

Both baseline_rules.classify_message() and incident_classifier.detect_incident()
return a single answer with no indication of how sure the rule engine actually
was. That's a real gap for a dispatcher-facing tool: "Fire, urgency 5" from a
message that hit three fire keywords should be trusted more than "Fire,
urgency 5" from a message that barely scraped past on one ambiguous word.

This module scores confidence for both classifiers WITHOUT changing their
existing return values (classify_message() and detect_incident() still return
exactly what they did before, so nothing that already depends on them breaks).
It reuses the exact same keyword rule tables those modules already use -
there is no second copy of the rules to drift out of sync.

Confidence formula (deliberately simple and explainable, not a black box -
this is a rule-based system, the confidence should be too):
  1. Start from how many keywords matched the WINNING category.
     1 match -> 0.65, 2 -> 0.80, 3+ -> capped at 0.95.
  2. Subtract 0.15 for every OTHER category that also had a keyword hit
     (ambiguity - the message plausibly means more than one thing).
  3. Floor of 0.30 - a rule match is still a signal, never treated as
     near-zero confidence even in the worst case.
  4. No keyword matched anything (NORMAL / UNKNOWN) -> flat 0.50. This is
     "no evidence either way", not "confident nothing is wrong" - distinct
     from a low score earned by conflicting evidence.

This also doubles as the data source for explainability (which keywords
fired, which categories conflicted) - see the "explainable AI" feature
built on top of this module.

Author : SETU Team
Version : 1.0
"""

from typing import Dict, List

from models.baseline_rules import URGENCY_RULES, NORMAL, contains_keyword, normalize_message as normalize_urgency_message
from models.incident_classifier import INCIDENT_RULES, UNKNOWN, contains_keyword as incident_contains_keyword, normalize_message as normalize_incident_message

MIN_CONFIDENCE = 0.30
MAX_CONFIDENCE = 0.95
NO_MATCH_CONFIDENCE = 0.50
PER_MATCH_STEP = 0.15
PER_CONFLICT_PENALTY = 0.15
BASE_CONFIDENCE = 0.50


def _score(matches_by_category: Dict, winning_category, no_match_value) -> dict:
    """Shared scoring logic for both urgency and incident confidence."""
    if not matches_by_category:
        return {
            "value": no_match_value,
            "confidence": NO_MATCH_CONFIDENCE,
            "matched_keywords": [],
            "conflicting_categories": [],
        }

    matched_keywords = matches_by_category[winning_category]
    conflicting = [cat for cat in matches_by_category if cat != winning_category]

    raw = BASE_CONFIDENCE + PER_MATCH_STEP * len(matched_keywords)
    raw -= PER_CONFLICT_PENALTY * len(conflicting)
    confidence = max(MIN_CONFIDENCE, min(MAX_CONFIDENCE, round(raw, 2)))

    return {
        "value": winning_category,
        "confidence": confidence,
        "matched_keywords": matched_keywords,
        "conflicting_categories": conflicting,
    }


def score_urgency(message: str) -> dict:
    """
    Returns:
        {
          "urgency": int,               # same value classify_message() would return
          "confidence": float,          # 0.30-0.95, or 0.50 if nothing matched
          "matched_keywords": [str],    # keywords that drove the winning urgency
          "conflicting_categories": [int],  # other urgency levels that also matched
        }
    """
    normalized = normalize_urgency_message(message)

    matches_by_level = {}
    for level, keywords in URGENCY_RULES.items():
        found = [kw for kw in keywords if contains_keyword(normalized, kw)]
        if found:
            matches_by_level[level] = found

    # URGENCY_RULES is defined CRITICAL -> HIGH -> MEDIUM -> LOW, so the first
    # key present in matches_by_level (iterating URGENCY_RULES' own order) is
    # exactly the winner classify_message() would already pick.
    winning_level = next((lvl for lvl in URGENCY_RULES if lvl in matches_by_level), None)

    result = _score(matches_by_level, winning_level, NORMAL)
    result["urgency"] = result.pop("value")
    return result


def score_incident(message: str) -> dict:
    """
    Returns:
        {
          "incident": str,                  # same value detect_incident() would return
          "confidence": float,              # 0.30-0.95, or 0.50 if nothing matched
          "matched_keywords": [str],
          "conflicting_categories": [str],  # other incident types that also matched
        }
    """
    normalized = normalize_incident_message(message)

    matches_by_type = {}
    for incident_type, keywords in INCIDENT_RULES.items():
        found = [kw for kw in keywords if incident_contains_keyword(normalized, kw)]
        if found:
            matches_by_type[incident_type] = found

    winning_type = next((t for t in INCIDENT_RULES if t in matches_by_type), None)

    result = _score(matches_by_type, winning_type, UNKNOWN)
    result["incident"] = result.pop("value")
    return result


if __name__ == "__main__":
    tests = [
        "Fire in my building",  # single clean match
        "aag lag gayi meri building mein madad karo",  # multiple matches, one category
        "Fire and flood both happening, help",  # deliberately ambiguous
        "Good morning",  # no match at all
    ]
    for msg in tests:
        print(f"Message: {msg}")
        print("  Urgency :", score_urgency(msg))
        print("  Incident:", score_incident(msg))
        print("-" * 50)
