"""
SETU AI - Unit tests for the models/ layer.

Was an empty stub before. Covers baseline_rules, incident_classifier,
priority_adjuster, duplicate_detector, confidence_scorer, explainability,
voice_service, and the pipeline/ai_service glue - including regression
tests for the bugs fixed on 2026-08-01:
  1. Hinglish (Roman-script Hindi) and women's-safety messages were
     silently scored as the lowest urgency (NORMAL) instead of CRITICAL.
  2. service/ai_service.py crashed every call with TypeError because
     emergency_id was never passed through to process_message().

...and on 2026-08-03:
  3. "asurakshit" (Hinglish for "unsafe") was missing from the Women
     Safety keyword lists - the one core-set miss in evaluation.
  4. The Gemini fallback's response was only ever attached as an
     informational "gemini_note" string - a correctly-classified
     message from Gemini never actually changed incident/urgency/
     priority, which defeated the whole point of having the fallback.

Run from the setu_ai_service/ project root (Windows):
    python -m pytest
"""

import pytest

from models.baseline_rules import classify_message, CRITICAL, HIGH, MEDIUM, LOW, NORMAL
from models.incident_classifier import detect_incident, FIRE, WOMEN_SAFETY, EARTHQUAKE, UNKNOWN
from models.priority_adjuster import adjust_priority, MIN_PRIORITY, MAX_PRIORITY
from models.duplicate_detector import check_duplicate, reset_clusters
from models.confidence_scorer import score_urgency, score_incident
from models.explainability import explain
from models.pipeline import process_message
from service.ai_service import analyze_emergency
from service.voice_service import transcribe_audio


@pytest.fixture(autouse=True)
def _reset_duplicate_clusters():
    """Duplicate detector keeps in-memory state - isolate every test."""
    reset_clusters()
    yield
    reset_clusters()


# ---------------------------------------------------------------------
# baseline_rules - urgency classification
# ---------------------------------------------------------------------

def test_english_fire_is_critical():
    assert classify_message("Fire in my building") == CRITICAL


def test_hinglish_fire_is_critical():
    # Regression: this used to fall through to NORMAL (1).
    assert classify_message("aag lag gayi meri building mein, madad karo") == CRITICAL


def test_hinglish_women_safety_is_critical():
    # Regression: this used to fall through to NORMAL (1).
    assert classify_message("bachao mujhe koi pareshan kar raha hai") == CRITICAL


def test_english_help_is_high():
    assert classify_message("Help me please") == HIGH


def test_generic_greeting_is_normal():
    assert classify_message("Good morning") == NORMAL


def test_medium_and_low_still_work():
    assert classify_message("Need assistance") == MEDIUM
    assert classify_message("Can anyone guide me?") == LOW


# ---------------------------------------------------------------------
# incident_classifier - incident type detection
# ---------------------------------------------------------------------

def test_english_fire_detected():
    assert detect_incident("Fire in my building") == FIRE


def test_hinglish_fire_detected():
    assert detect_incident("ghar mein aag lag gayi hai jaldi aao") == FIRE


def test_women_safety_detected_english_and_hinglish():
    assert detect_incident("someone is stalking me, unsafe") == WOMEN_SAFETY
    assert detect_incident("bachao koi mujhe pareshan kar raha hai") == WOMEN_SAFETY


def test_earthquake_detected():
    assert detect_incident("earthquake, building shaking") == EARTHQUAKE
    assert detect_incident("bhukamp aa gaya sab log bahar bhaago") == EARTHQUAKE


def test_unrelated_message_is_unknown():
    assert detect_incident("Good morning") == UNKNOWN


# ---------------------------------------------------------------------
# priority_adjuster
# ---------------------------------------------------------------------

def test_building_collapse_gets_largest_boost():
    boosted = adjust_priority(5, relay_count=1, age_seconds=10, incident_type="Building Collapse")
    assert boosted == MAX_PRIORITY  # clamps at 5.0, boost pushes it there


def test_women_safety_and_earthquake_get_high_boost():
    ws = adjust_priority(4, relay_count=1, age_seconds=10, incident_type="Women Safety")
    eq = adjust_priority(4, relay_count=1, age_seconds=10, incident_type="Earthquake")
    assert ws == pytest.approx(4.45)
    assert eq == pytest.approx(4.45)


def test_stale_relayed_message_gets_penalized():
    fresh = adjust_priority(3, relay_count=1, age_seconds=10, incident_type="Unknown")
    stale_and_relayed = adjust_priority(3, relay_count=10, age_seconds=200, incident_type="Unknown")
    assert stale_and_relayed < fresh


def test_priority_never_exceeds_bounds():
    assert adjust_priority(10, 0, 0, "Building Collapse") <= MAX_PRIORITY
    assert adjust_priority(-5, 100, 100, "Unknown") >= MIN_PRIORITY


# ---------------------------------------------------------------------
# duplicate_detector
# ---------------------------------------------------------------------

def test_identical_message_flagged_duplicate():
    first = check_duplicate("Fire in Block A", "e1")
    second = check_duplicate("Fire in Block A", "e2")
    assert first["is_duplicate"] is False
    assert second["is_duplicate"] is True
    assert second["matched_cluster_id"] == "e1"


def test_unrelated_message_not_duplicate():
    check_duplicate("Fire in Block A", "e1")
    result = check_duplicate("Flood near the river", "e2")
    assert result["is_duplicate"] is False


def test_similar_text_nearby_location_merges():
    # ~30m apart in central Delhi -> same incident.
    check_duplicate("Fire in Block A", "e1", latitude=28.6139, longitude=77.2090)
    result = check_duplicate("Building fire in Block A", "e2", latitude=28.6141, longitude=77.2092)
    assert result["is_duplicate"] is True
    assert result["distance_meters"] < 100


def test_similar_text_far_apart_does_not_merge():
    # Same wording, Delhi vs Gurgaon (~25km apart) -> two separate incidents,
    # not one merged report. This is the exact bug geo-dedup was added to fix:
    # text similarity alone would have wrongly merged these.
    check_duplicate("Fire in Block A", "e1", latitude=28.6139, longitude=77.2090)
    result = check_duplicate("Building fire in Block A", "e2", latitude=28.4595, longitude=77.0266)
    assert result["is_duplicate"] is False


def test_missing_gps_falls_back_to_text_only():
    # (0.0, 0.0) is the packet spec's documented no-GPS-fix fallback, not a
    # real location - dedup must not treat it as "far away" and should fall
    # back to text+time matching instead.
    check_duplicate("Fire in Block A", "e1", latitude=28.6139, longitude=77.2090)
    result = check_duplicate("Building fire in Block A", "e2", latitude=0.0, longitude=0.0)
    assert result["is_duplicate"] is True
    assert result["distance_meters"] is None


def test_dedup_never_crashes_regardless_of_embedding_model_availability():
    # This must hold whether or not sentence-transformers is installed -
    # match_method reports which path was actually used, but is_duplicate
    # detection itself must always produce a clean result either way.
    check_duplicate("Fire in Block A", "e1", latitude=28.6139, longitude=77.2090)
    result = check_duplicate("Building fire in Block A", "e2", latitude=28.6141, longitude=77.2092)
    assert result["match_method"] in ("embedding", "lexical")
    assert result["is_duplicate"] is True


def test_response_always_reports_a_match_method():
    result = check_duplicate("Hello everyone", "e1")
    assert result["match_method"] in ("embedding", "lexical")


# ---------------------------------------------------------------------
# confidence_scorer
# ---------------------------------------------------------------------

def test_single_clean_match_has_moderate_confidence():
    result = score_urgency("Fire in my building")
    assert result["urgency"] == CRITICAL
    assert result["confidence"] == pytest.approx(0.65)
    assert result["matched_keywords"] == ["fire"]
    assert result["conflicting_categories"] == []


def test_multiple_matches_raise_confidence():
    single = score_incident("Fire in my building")
    multiple = score_incident("aag lag gayi meri building mein madad karo")
    assert multiple["confidence"] > single["confidence"]


def test_ambiguous_message_lowers_confidence():
    clean = score_incident("Fire in my building")
    ambiguous = score_incident("Fire and flood both happening, help")
    assert ambiguous["conflicting_categories"] == ["Flood"]
    assert ambiguous["confidence"] < clean["confidence"]


def test_no_match_gets_flat_baseline_confidence():
    result = score_urgency("Good morning")
    assert result["urgency"] == NORMAL
    assert result["confidence"] == 0.50
    assert result["matched_keywords"] == []


def test_confidence_never_leaves_valid_range():
    for msg in ["Fire in my building", "Good morning", "aag lag gayi madad karo bachao"]:
        u = score_urgency(msg)
        i = score_incident(msg)
        assert 0.30 <= u["confidence"] <= 0.95 or u["confidence"] == 0.50
        assert 0.30 <= i["confidence"] <= 0.95 or i["confidence"] == 0.50


# ---------------------------------------------------------------------
# explainability
# ---------------------------------------------------------------------

def test_explanation_mentions_matched_keyword():
    report = explain("Fire in my building")
    assert "fire" in report["urgency_explanation"]
    assert "fire" in report["incident_explanation"]
    assert report["urgency"] == CRITICAL
    assert report["incident"] == FIRE


def test_explanation_for_unmatched_message_says_no_keywords():
    report = explain("Good morning")
    assert "No urgency keywords matched" in report["urgency_explanation"]
    assert "No incident-type keywords matched" in report["incident_explanation"]


def test_explanation_mentions_conflict_when_ambiguous():
    report = explain("Fire and flood both happening, help")
    assert "also partially matched" in report["incident_explanation"]


# ---------------------------------------------------------------------
# pipeline / ai_service glue
# ---------------------------------------------------------------------

def test_pipeline_does_not_overwrite_caller_priority_field_name():
    # The packet's own sender-declared "priority" is a separate concept
    # from this service's AI-assessed priority score. This test just
    # locks in the current output shape so a future change doesn't
    # silently rename/merge them without anyone noticing.
    result = process_message("Fire in my building", relay_count=1, age_seconds=5, emergency_id="e1")
    assert set(result.keys()) >= {
        "message", "emergency_id", "incident", "incident_confidence", "incident_explanation",
        "urgency", "urgency_confidence", "urgency_explanation",
        "priority", "is_duplicate", "matched_cluster_id", "similarity",
        "match_method", "distance_meters",
    }


def test_ai_service_analyze_emergency_does_not_crash():
    # Regression: this used to raise TypeError on every call because
    # emergency_id was never forwarded to process_message().
    result = analyze_emergency("Fire in my building", emergency_id="e1", relay_count=0, age_seconds=0)
    assert result["incident"] == FIRE


# ---------------------------------------------------------------------
# voice_service
# ---------------------------------------------------------------------

def test_transcribe_audio_missing_file_returns_none_not_crash():
    # Whisper is a heavy model load - this test deliberately does NOT
    # exercise real transcription (too slow for a unit test suite). It
    # only locks in the graceful-failure contract: a missing/bad file
    # must return None, never raise, so callers (the /analyze-voice
    # route) can turn that into a clean 422 instead of a 500 crash.
    assert transcribe_audio("this_file_does_not_exist.wav") is None


# ---------------------------------------------------------------------
# Regression tests for 2026-08-03 fixes
# ---------------------------------------------------------------------

def test_asurakshit_is_women_safety():
    # Regression: "asurakshit" (Hinglish for "unsafe") was missing from
    # both keyword lists, so this exact message was the one core-set
    # miss in the 2026-08-02 evaluation run (fell through to
    # Unknown/urgency-4 instead of Women Safety/urgency-5).
    assert detect_incident("main akeli hoon aur asurakshit mehsoos kar rahi hoon") == WOMEN_SAFETY
    assert classify_message("main akeli hoon aur asurakshit mehsoos kar rahi hoon") == CRITICAL


def test_gemini_parse_valid_response():
    from service.gemini_service import parse_gemini_response
    raw = "Incident Type: Fire\nSeverity: Critical\nShort Summary: Building on fire, people trapped"
    parsed = parse_gemini_response(raw)
    assert parsed["incident"] == "Fire"
    assert parsed["urgency"] == 5
    assert parsed["summary"] == "Building on fire, people trapped"


def test_gemini_parse_never_crashes_on_malformed_input():
    from service.gemini_service import parse_gemini_response
    for bad_input in ["", None, "Gemini Error: timeout", "just some unrelated free text"]:
        parsed = parse_gemini_response(bad_input)
        assert parsed == {"incident": None, "urgency": None, "summary": None}


def test_gemini_fallback_actually_updates_pipeline_decision(monkeypatch):
    # Regression: previously, a successful Gemini classification was only
    # attached as an opaque "gemini_note" string - incident/urgency/priority
    # stayed "Unknown"/1/1.0 even when Gemini correctly identified the
    # emergency. This locks in the fix: a parseable Gemini response must
    # actually change the fields a dispatcher would act on.
    import config
    import models.pipeline as pipeline_module
    monkeypatch.setattr(pipeline_module, "GEMINI_ENABLED", True)

    import service.gemini_service as gemini_module
    monkeypatch.setattr(
        gemini_module, "analyze_with_gemini",
        lambda msg: "Incident Type: Fire\nSeverity: Critical\nShort Summary: test",
    )

    result = process_message(
        "unusual distress situation happening right now",  # matches no keyword rule
        relay_count=1, age_seconds=5, emergency_id="e-gemini-regression",
    )
    assert result["incident"] == FIRE
    assert result["urgency"] == CRITICAL
    assert result["priority"] > MIN_PRIORITY
    assert result["gemini_assisted"] is True


def test_gemini_fallback_leaves_unknown_when_response_unparseable(monkeypatch):
    import models.pipeline as pipeline_module
    monkeypatch.setattr(pipeline_module, "GEMINI_ENABLED", True)

    import service.gemini_service as gemini_module
    monkeypatch.setattr(gemini_module, "analyze_with_gemini", lambda msg: "some unparseable free text")

    result = process_message(
        "unusual distress situation happening right now",
        relay_count=1, age_seconds=5, emergency_id="e-gemini-regression-2",
    )
    assert result["incident"] == UNKNOWN
    assert result["gemini_assisted"] is False
