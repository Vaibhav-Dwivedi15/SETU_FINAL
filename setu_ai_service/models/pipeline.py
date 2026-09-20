from config import GEMINI_ENABLED
from models.baseline_rules import classify_message
from models.incident_classifier import detect_incident, UNKNOWN
from models.duplicate_detector import check_duplicate
from models.priority_adjuster import adjust_priority
from utils.logger import get_logger

logger = get_logger(__name__)


def process_message(
    message: str,
    relay_count: int,
    age_seconds: int,
    emergency_id: str,
) -> dict:

    dup_result = check_duplicate(message, emergency_id)

    incident = detect_incident(message)
    urgency = classify_message(message)

    gemini_note = None
    if incident == UNKNOWN and GEMINI_ENABLED:
        # Rule-based keyword matching couldn't classify this one — only
        # now do we pay the latency/cost of a live Gemini call, and only
        # because the feature flag is explicitly on. Never on the
        # default/critical path.
        from service.gemini_service import analyze_with_gemini
        gemini_note = analyze_with_gemini(message)
        logger.info(f"Gemini fallback used for unclassified message: {emergency_id}")

    priority = adjust_priority(urgency, relay_count, age_seconds, incident)

    logger.info(
        f"Processed {emergency_id}: incident={incident} urgency={urgency} "
        f"priority={priority} duplicate={dup_result['is_duplicate']}"
    )

    result = {
        "message": message,
        "emergency_id": emergency_id,
        "incident": incident,
        "urgency": urgency,
        "priority": priority,
        "is_duplicate": dup_result["is_duplicate"],
        "matched_cluster_id": dup_result["matched_cluster_id"],
        "similarity": dup_result["similarity"],
    }
    if gemini_note:
        result["gemini_note"] = gemini_note

    return result


if __name__ == "__main__":
    result = process_message(
        "Fire in my building",
        relay_count=2,
        age_seconds=30,
        emergency_id="test-e1",
    )
    print(result)
