"""
Wrapper around Vaishnavi's setu_ai_service (vendored under
Backend/setu_ai_service/ -- see that folder's own HANDOFF_AYUSH_BACKEND.md).

WHY THIS FILE EXISTS (the sys.path issue):
Every module inside setu_ai_service uses absolute imports that assume
the setu_ai_service folder ITSELF is the sys.path root -- e.g.
service/ai_service.py does `from models.pipeline import process_message`,
not `from setu_ai_service.models.pipeline import ...`. Importing it
normally (`from setu_ai_service.service.ai_service import analyze_emergency`)
crashes with `ModuleNotFoundError: No module named 'models'`, because
Python resolves that bare `models` against sys.path, and setu_ai_service
was never added to it. This file adds the fix once, at import time, so
every other module in this backend can just call analyze() below without
knowing any of this.

DEDUP DECISION -- REVERSED (see history below):
Originally (first integration pass), this backend's own
incident_service.py / deduplication_service.py was kept as the SOLE
source of truth for "is this a duplicate," and the AI service's
is_duplicate/matched_cluster_id was deliberately dropped here, because
that dedup was already load-tested (5/5 clean runs, 50 concurrent) and
the AI service's was unproven in this pipeline.

That decision has since been REVERSED per team direction: the AI
service's dedup (geo + time + lexical + multilingual embedding) is now
the source of truth, via is_duplicate/matched_cluster_id below.
incident_service.py's own find_matching_incident() is kept only as a
fallback for when ai_result is None (AI call failed) -- see
incident_service.py's handle_sos_packet for that logic.

KNOWN OPERATIONAL RISK (confirmed by reading duplicate_detector.py
directly, not assumed): its cluster state is a plain in-memory Python
list -- the AI team's own code comment states it resets on server
restart and won't stay consistent across multiple worker processes.
Accepted for now (single-instance demo); a real fix (Redis or
DB-backed clusters) is needed before anything longer-lived than a demo.
SETU_AI_EMBEDDING_DEDUP_ENABLED=true is required for this dedup to
actually be richer than what it replaced -- without it, this is
lexical+geo+time only, which is not meaningfully better than the
dedup it replaced, just less durable. Confirm that flag is on before
trusting this path.

FAILURE POSTURE: analyze() never raises. A broken/slow/misconfigured AI
service (missing optional deps, Gemini timeout, etc.) must not block
packet ingestion -- incident creation already works without it. Any
exception is logged and swallowed; callers get None and should treat
that exactly like "AI fields not available yet, fall back to our own
dedup," same as if AI integration didn't exist.
"""

import logging

from app.utils.setu_ai_import_guard import ensure_setu_ai_service_importable

ensure_setu_ai_service_importable()

logger = logging.getLogger(__name__)


def analyze(message: str, emergency_id: str, relay_count: int, age_seconds: int,
            latitude: float = 0.0, longitude: float = 0.0) -> dict | None:
    """
    Returns setu_ai_service's analyze_emergency() output, reshaped to
    this backend's field names, or None if the AI service raised for
    any reason. Now includes is_duplicate/matched_cluster_id -- this IS
    the dedup source of truth as of the reversed decision above.
    """
    try:
        from service.ai_service import analyze_emergency  # setu_ai_service's own package layout
    except Exception:
        logger.exception("setu_ai_service import failed -- AI fields will be unavailable")
        return None

    try:
        result = analyze_emergency(
            message=message,
            emergency_id=emergency_id,
            relay_count=relay_count,
            age_seconds=max(age_seconds, 0),  # clock skew guard, per setu_ai_service's own handoff doc
            latitude=latitude,
            longitude=longitude,
        )
    except Exception:
        logger.exception(f"AI analysis failed for emergency_id={emergency_id}")
        return None

    return {
        "ai_incident_type": result.get("incident"),
        "ai_incident_confidence": result.get("incident_confidence"),
        "ai_incident_explanation": result.get("incident_explanation"),
        "ai_urgency": result.get("urgency"),
        "ai_urgency_confidence": result.get("urgency_confidence"),
        "ai_urgency_explanation": result.get("urgency_explanation"),
        "ai_priority": result.get("priority"),
        "is_duplicate": result.get("is_duplicate"),
        "matched_cluster_id": result.get("matched_cluster_id"),
        # Evidence for the explainable dedup decision (Block 2).
        "similarity": result.get("similarity"),
        "match_method": result.get("match_method"),
        "distance_meters": result.get("distance_meters"),
        "dedup_reason": result.get("dedup_reason"),
    }
