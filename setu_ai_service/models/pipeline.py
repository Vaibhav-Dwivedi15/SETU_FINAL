"""
SETU AI - End-to-End Processing Pipeline
"""

from typing import Optional, Dict, Any
from config import GEMINI_ENABLED
from utils.security import sanitize_and_audit_input
from models.baseline_rules import classify_message
from models.incident_classifier import detect_incident, UNKNOWN
from models.duplicate_detector import check_duplicate
from models.priority_adjuster import adjust_priority, get_priority_tier
from models.disaster_intelligence import (
    extract_damage_info,
    extract_resource_info,
    extract_missing_person_info,
)
from models.responder_intelligence import generate_responder_brief
from utils.logger import get_logger

logger = get_logger(__name__)


def process_message(
    message: str,
    relay_count: int,
    age_seconds: int,
    emergency_id: str,
    latitude: Optional[float] = None,
    longitude: Optional[float] = None,
) -> Dict[str, Any]:

    # 1. Security & Prompt Injection Sanitization
    sanitized_msg, is_flagged, threats = sanitize_and_audit_input(message)
    if is_flagged:
        logger.warning(f"Security Alert on {emergency_id}: {threats}")

    # 2. Incident Classification (on sanitized text)
    incident = detect_incident(sanitized_msg) if sanitized_msg else UNKNOWN

    # 3. Geolocation-aware Deduplication
    dup_result = check_duplicate(
        message=sanitized_msg,
        emergency_id=emergency_id,
        incident_type=incident,
        latitude=latitude,
        longitude=longitude,
    )

    # 4. Urgency and Priority Calculation (Guarded against injection overrides)
    urgency = classify_message(sanitized_msg) if sanitized_msg else 1
    numeric_priority = adjust_priority(urgency, relay_count, age_seconds, incident)
    priority_tier = get_priority_tier(numeric_priority)

    # 5. Recovery Intelligence Extraction
    damage_info = extract_damage_info(sanitized_msg)
    resource_info = extract_resource_info(sanitized_msg)
    missing_info = extract_missing_person_info(sanitized_msg)

    # 6. Responder Summary Generation
    loc_str = f"({latitude:.4f}, {longitude:.4f})" if latitude and longitude else "Coordinates Unset"
    brief = generate_responder_brief(
        emergency_id=emergency_id,
        incident=incident,
        priority=priority_tier,
        damage_info=damage_info.model_dump(),
        resource_info=resource_info.model_dump(),
        missing_info=missing_info.model_dump(),
        location_str=loc_str,
    )

    # 7. Optional AI Enrichment
    gemini_note = None
    ai_enhanced = False
    if incident == UNKNOWN and GEMINI_ENABLED and sanitized_msg:
        try:
            from service.gemini_service import analyze_with_gemini
            gemini_note = analyze_with_gemini(sanitized_msg)
            ai_enhanced = True
        except Exception as e:
            logger.warning(f"Gemini fallback failed: {e}")

    return {
        "emergency_id": emergency_id,
        "message": sanitized_msg,
        "incident": incident,
        "urgency": str(urgency),
        "priority": priority_tier,
        "duplicate_info": dup_result,
        "damage_assessment": damage_info.model_dump(),
        "resource_assessment": resource_info.model_dump(),
        "missing_person_assessment": missing_info.model_dump(),
        "responder_brief": brief,
        "security_audit": {"is_flagged": is_flagged, "threats": threats},
        "ai_enhanced": ai_enhanced,
        "gemini_note": gemini_note,
    }
