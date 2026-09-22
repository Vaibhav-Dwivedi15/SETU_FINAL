"""
SETU AI - End-to-End Processing Pipeline
"""

from typing import Optional, Dict, Any
from config import GEMINI_ENABLED
from models.baseline_rules import classify_message
from models.incident_classifier import detect_incident, UNKNOWN
from models.duplicate_detector import check_duplicate
from models.priority_adjuster import adjust_priority, get_priority_tier
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

    # 1. Incident Classification
    incident = detect_incident(message)

    # 2. Geolocation-aware Deduplication (P0 Boundary)
    dup_result = check_duplicate(
        message=message,
        emergency_id=emergency_id,
        incident_type=incident,
        latitude=latitude,
        longitude=longitude,
    )

    # 3. Urgency and Priority Tier Calculation
    urgency = classify_message(message)
    numeric_priority = adjust_priority(urgency, relay_count, age_seconds, incident)
    priority_tier = get_priority_tier(numeric_priority)

    # 4. Optional AI Enrichment
    gemini_note = None
    ai_enhanced = False
    if incident == UNKNOWN and GEMINI_ENABLED:
        try:
            from service.gemini_service import analyze_with_gemini
            gemini_note = analyze_with_gemini(message)
            ai_enhanced = True
            logger.info(f"Gemini fallback used for unclassified message: {emergency_id}")
        except Exception as e:
            logger.warning(f"Gemini service unavailable, falling back to rule baseline: {e}")

    logger.info(
        f"Processed {emergency_id}: incident={incident} urgency={urgency} "
        f"priority_score={numeric_priority} tier={priority_tier} duplicate={dup_result['is_duplicate']}"
    )

    return {
        "emergency_id": emergency_id,
        "message": message,
        "incident": incident,
        "urgency": str(urgency),
        "priority": priority_tier,
        "duplicate_info": dup_result,
        "ai_enhanced": ai_enhanced,
        "gemini_note": gemini_note,
    }
