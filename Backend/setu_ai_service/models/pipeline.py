from config import GEMINI_ENABLED, GEMINI_CONFIDENCE
from models.explainability import explain
from models.incident_classifier import UNKNOWN
from models.duplicate_detector import check_duplicate
from models.priority_adjuster import adjust_priority
from utils.logger import get_logger

logger = get_logger(__name__)


def process_message(
    message: str,
    relay_count: int,
    age_seconds: int,
    emergency_id: str,
    latitude: float = 0.0,
    longitude: float = 0.0,
) -> dict:
    # latitude/longitude default to 0.0 to match the mesh packet's own
    # documented no-GPS-fix fallback (Section 3 of the project handoff).
    # check_duplicate() treats (0.0, 0.0) as "no usable location" and
    # falls back to text+time-only matching rather than wrongly using
    # null-island coordinates as a real position.
    dup_result = check_duplicate(message, emergency_id, latitude=latitude, longitude=longitude)

    # explain() runs the same rule-based classification classify_message()/
    # detect_incident() always did, but also returns a confidence score and
    # a human-readable reason for both the urgency and incident decisions
    # (see models/confidence_scorer.py and models/explainability.py).
    explanation = explain(message)
    incident = explanation["incident"]
    urgency = explanation["urgency"]

    gemini_note = None
    gemini_assisted = False
    if incident == UNKNOWN and GEMINI_ENABLED:
        # Rule-based keyword matching couldn't classify this one - only
        # now do we pay the latency/cost of a live Gemini call, and only
        # because the feature flag is explicitly on. Never on the
        # default/critical path.
        from service.gemini_service import analyze_with_gemini, parse_gemini_response
        gemini_note = analyze_with_gemini(message)
        parsed = parse_gemini_response(gemini_note)

        # THE FIX: previously gemini_note was attached to the response
        # and nothing else happened - incident/urgency/priority stayed
        # "Unknown"/1/1.0 even when Gemini correctly identified the
        # emergency. Now, whatever Gemini successfully parsed actually
        # overrides those fields, so a dispatcher-facing response
        # reflects what was actually found. GEMINI_CONFIDENCE is a fixed,
        # documented placeholder (not on the same 0.30-0.95 scale the
        # rule engine's confidence_scorer computes) - it exists so the
        # response can't be mistaken for "as confident as a 3-keyword
        # rule match", while still signaling "a real classification, not
        # a guess".
        if parsed["incident"] and parsed["incident"] != UNKNOWN:
            incident = parsed["incident"]
            explanation["incident"] = incident
            explanation["incident_confidence"] = GEMINI_CONFIDENCE
            explanation["incident_explanation"] = (
                f"Rule engine returned Unknown; Gemini fallback classified this as '{incident}'."
                + (f" {parsed['summary']}" if parsed["summary"] else "")
            )
            gemini_assisted = True
        if parsed["urgency"] is not None:
            urgency = parsed["urgency"]
            explanation["urgency"] = urgency
            explanation["urgency_confidence"] = GEMINI_CONFIDENCE
            explanation["urgency_explanation"] = (
                f"Rule engine had no urgency keyword match; Gemini fallback assessed this as urgency {urgency}."
            )
            gemini_assisted = True

        logger.info(
            f"Gemini fallback used for {emergency_id}: "
            f"parsed_incident={parsed['incident']} parsed_urgency={parsed['urgency']} "
            f"applied={gemini_assisted}"
        )

    priority = adjust_priority(urgency, relay_count, age_seconds, incident)

    logger.info(
        f"Processed {emergency_id}: incident={incident} urgency={urgency} "
        f"priority={priority} duplicate={dup_result['is_duplicate']}"
    )

    result = {
        "message": message,
        "emergency_id": emergency_id,
        "incident": incident,
        "incident_confidence": explanation["incident_confidence"],
        "incident_explanation": explanation["incident_explanation"],
        "urgency": urgency,
        "urgency_confidence": explanation["urgency_confidence"],
        "urgency_explanation": explanation["urgency_explanation"],
        "priority": priority,
        "is_duplicate": dup_result["is_duplicate"],
        "matched_cluster_id": dup_result["matched_cluster_id"],
        "similarity": dup_result["similarity"],
        "match_method": dup_result["match_method"],
        "distance_meters": dup_result["distance_meters"],
        "dedup_reason": dup_result["dedup_reason"],
    }
    if gemini_note:
        result["gemini_note"] = gemini_note
        result["gemini_assisted"] = gemini_assisted

    return result


if __name__ == "__main__":
    result = process_message(
        "Fire in my building",
        relay_count=2,
        age_seconds=30,
        emergency_id="test-e1",
        latitude=28.6139,
        longitude=77.2090,
    )
    print(result)
