"""
SETU AI - API Response Schemas

Was an empty stub before. Defines the response shape returned by
models/pipeline.py's process_message() and exposed via /analyze, so
FastAPI can validate and document it instead of returning a bare dict.

Field names deliberately do NOT collide with the mesh packet's own
sender-declared `priority` field (Section 3 of the project handoff):
this service's `priority` is the AI-assessed score, separate from and
additive to the packet's client-set baseline priority. The caller
(Backend Lead) is responsible for keeping both values distinct rather
than overwriting one with the other.
"""

from typing import Optional

from pydantic import BaseModel, Field


class TriageResponse(BaseModel):
    message: str = Field(..., description="The original distress message text.")
    emergency_id: str = Field(..., description="Matches the packet's emergency_id.")
    incident: str = Field(..., description="Detected incident type, e.g. 'Fire', 'Women Safety', 'Unknown'.")
    incident_confidence: float = Field(
        ..., ge=0.0, le=1.0,
        description="0.30-0.95 based on keyword match strength, or 0.50 if nothing matched (see models/confidence_scorer.py).",
    )
    incident_explanation: str = Field(
        ..., description="Human-readable reason for the incident classification, e.g. which keywords matched.",
    )
    urgency: int = Field(..., ge=1, le=5, description="Rule-based urgency score, 1 (normal) to 5 (critical).")
    urgency_confidence: float = Field(
        ..., ge=0.0, le=1.0,
        description="0.30-0.95 based on keyword match strength, or 0.50 if nothing matched.",
    )
    urgency_explanation: str = Field(
        ..., description="Human-readable reason for the urgency score, e.g. which keywords matched.",
    )
    priority: float = Field(
        ...,
        ge=1.0,
        le=5.0,
        description=(
            "AI-assessed priority after incident/relay/age adjustment. "
            "This is NOT the packet's own sender-declared priority field - "
            "keep both distinct downstream."
        ),
    )
    is_duplicate: bool = Field(..., description="True if this matches an already-seen active incident cluster.")
    matched_cluster_id: str = Field(..., description="emergency_id this report is clustered under.")
    similarity: float = Field(..., ge=0.0, le=1.0, description="Similarity score to the matched cluster, if any.")
    match_method: str = Field(
        ...,
        description=(
            "'embedding' if the multilingual embedding model was used (catches cross-language/"
            "paraphrased duplicates, e.g. Hinglish vs English), 'lexical' if it fell back to plain "
            "difflib text overlap (embedding model not installed/downloaded, or feature-flagged off)."
        ),
    )
    distance_meters: Optional[float] = Field(
        None,
        description=(
            "Distance in meters to the matched cluster's location, if both reports had a "
            "usable GPS fix. None if not a duplicate, or if either side's GPS was unavailable "
            "(the packet spec's 0.0/0.0 fallback), in which case matching fell back to text+time only."
        ),
    )
    dedup_reason: Optional[str] = Field(
        None,
        description=(
            "Why the duplicate decision was made: 'text_and_geo_match', "
            "'text_match_location_unverified' (one side had no GPS fix), or "
            "'no_similar_recent_report'."
        ),
    )
    gemini_note: Optional[str] = Field(
        None,
        description="Only present when the rule-based classifier returned Unknown AND the Gemini fallback flag is on.",
    )
    gemini_assisted: Optional[bool] = Field(
        None,
        description=(
            "True if Gemini's response was successfully parsed and actually changed the "
            "incident/urgency fields above (not just attached as gemini_note). False if Gemini "
            "was called but its response couldn't be parsed into a usable classification - in "
            "that case incident/urgency are still whatever the rule engine originally returned. "
            "None if Gemini wasn't invoked at all."
        ),
    )
