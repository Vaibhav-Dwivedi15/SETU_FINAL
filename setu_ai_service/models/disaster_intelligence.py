"""
SETU AI - Disaster Intelligence Engine
Performs offline entity extraction for Damage, Resources, and Missing Persons.
"""

import re
from typing import Dict, Any, List, Optional
from models.response_models import DamageAssessment, ResourceAssessment, MissingPersonAssessment

# Asset dictionaries
INFRASTRUCTURE_PATTERNS = {
    "Hospital": [r"\bhospitals?\b", r"\bclinics?\b", r"\bphc\b", r"\bhealth center\b"],
    "Bridge": [r"\bbridges?\b", r"\bflyovers?\b", r"\bpul\b"],
    "Road": [r"\broads?\b", r"\bhighways?\b", r"\bstroots?\b", r"\blanes?\b", r"\brasta\b"],
    "School": [r"\bschools?\b", r"\bcolleges?\b", r"\buniversity\b"],
    "Residential Building": [r"\bbuildings?\b", r"\bhouses?\b", r"\bflats?\b", r"\bapartments?\b", r"\bmakan\b"],
    "Power Grid": [r"\bpower grid\b", r"\btransformer\b", r"\belectric pole\b", r"\blight\b"],
    "Water Supply": [r"\bwater pipeline\b", r"\btank\b", r"\bwater plant\b"],
}

RESOURCE_PATTERNS = {
    "Water": [r"\bwaters?\b", r"\bdrinking water\b", r"\bpaani\b", r"\bpani\b", r"\bbottles?\b"],
    "Food": [r"\bfoods?\b", r"\brations?\b", r"\bgroceries?\b", r"\bstarving\b", r"\bkhaana\b", r"\bmeal\b", r"\bpackets?\b"],
    "Medical": [r"\bmedicines?\b", r"\bfirst aid\b", r"\bbandages?\b", r"\binsulin\b", r"\bdawa\b", r"\bdawai\b", r"\boxygens?\b"],
    "Shelter": [r"\bshelters?\b", r"\btents?\b", r"\btarpaulins?\b", r"\btirpal\b", r"\broof\b"],
    "Clothing": [r"\bclothes?\b", r"\bblankets?\b", r"\bwarm clothing\b", r"\bchaddar\b", r"\bkapde\b"],
    "Power": [r"\bpower\b", r"\bgenerators?\b", r"\bbatteries?\b", r"\btorches?\b", r"\bcharging\b"],
}


def extract_people_count(text: str) -> Optional[int]:
    """Extract explicit number of people affected/trapped."""
    match = re.search(r"(\d+)\s*(people|persons|citizens|children|families|members|log|bacche)", text, re.IGNORECASE)
    if match:
        return int(match.group(1))
    return None


def extract_damage_info(text: str) -> DamageAssessment:
    lower_text = text.lower()
    detected_asset = None
    for asset, patterns in INFRASTRUCTURE_PATTERNS.items():
        if any(re.search(pat, lower_text) for pat in patterns):
            detected_asset = asset
            break

    # Determine severity
    severity = "NONE"
    has_damage = False
    if any(w in lower_text for w in ["crushed", "destroyed", "collapsed", "flattened", "washed away"]):
        severity = "CATASTROPHIC"
        has_damage = True
    elif any(w in lower_text for w in ["severe", "major damage", "submerged", "broken", "critical"]):
        severity = "SEVERE"
        has_damage = True
    elif any(w in lower_text for w in ["damaged", "cracked", "leak", "partial"]):
        severity = "MODERATE"
        has_damage = True
    elif detected_asset:
        severity = "MINOR"
        has_damage = True

    affected = extract_people_count(lower_text)

    return DamageAssessment(
        has_damage=has_damage,
        asset_type=detected_asset,
        severity=severity,
        estimated_affected=affected,
        details=text.strip() if has_damage else None,
    )


def extract_resource_info(text: str) -> ResourceAssessment:
    lower_text = text.lower()
    categories: List[str] = []

    for cat, patterns in RESOURCE_PATTERNS.items():
        if any(re.search(pat, lower_text) for pat in patterns):
            categories.append(cat)

    if not categories:
        return ResourceAssessment(needs_resources=False, categories=[], urgency="STANDARD")

    urgency = "STANDARD"
    if any(w in lower_text for w in ["urgent", "emergency", "immediately", "dying", "critical", "running out"]):
        urgency = "IMMEDIATE"
    elif any(w in lower_text for w in ["needed", "required", "shortage"]):
        urgency = "HIGH"

    return ResourceAssessment(
        needs_resources=True,
        categories=categories,
        urgency=urgency,
        details=text.strip(),
    )


def extract_missing_person_info(text: str) -> MissingPersonAssessment:
    lower_text = text.lower()
    if not any(w in lower_text for w in ["missing", "lost", "separated", "untraceable", "last seen"]):
        return MissingPersonAssessment(is_missing_report=False)

    # Extract Age
    age = None
    age_match = re.search(r"(\d{1,2})\s*(years?\s*old|yr|yo|saal)", lower_text)
    if age_match:
        age = int(age_match.group(1))

    # Extract Gender
    gender = None
    if re.search(r"\b(boy|male|man|son|brother|father|he|ladka)\b", lower_text):
        gender = "MALE"
    elif re.search(r"\b(girl|female|woman|daughter|sister|mother|she|ladki)\b", lower_text):
        gender = "FEMALE"

    # Extract Name pattern (e.g. "named Rahul" or "name is Rahul")
    name = None
    name_match = re.search(r"(?:named|name is|called)\s+([A-Z][a-z]+)", text)
    if name_match:
        name = name_match.group(1)

    return MissingPersonAssessment(
        is_missing_report=True,
        name=name,
        age=age,
        gender=gender,
        last_seen=text.strip(),
    )
