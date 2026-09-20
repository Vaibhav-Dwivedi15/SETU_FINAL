"""
SETU AI - Gemini Service

Optional enhancement layer — see config.GEMINI_ENABLED. Client
initialization is lazy (only happens on the first real call), so simply
importing this module never crashes the service even with no API key
configured. The previous version built the client at import time, which
meant any accidental import anywhere in the codebase would crash the
whole app if .env was missing — that's fixed here.
"""

import os
import re
from pathlib import Path

from dotenv import load_dotenv

from config import GEMINI_MODEL_NAME
from prompts.emergency_prompt import EMERGENCY_ANALYSIS_PROMPT, INCIDENT_TYPES

BASE_DIR = Path(__file__).resolve().parents[1]
load_dotenv(BASE_DIR / ".env")

_client = None

# Severity word -> the pipeline's own 1-5 urgency scale (see
# models/baseline_rules.py's CRITICAL/HIGH/MEDIUM/LOW/NORMAL constants).
# Kept generous on synonyms since an LLM won't always use the exact
# word the prompt asked for, even when told to.
_SEVERITY_TO_URGENCY = {
    "critical": 5, "severe": 5, "extreme": 5,
    "high": 4, "urgent": 4,
    "medium": 3, "moderate": 3,
    "low": 2, "minor": 2,
    "normal": 1, "none": 1,
}

# Case-insensitive lookup back to the pipeline's exact incident-type
# strings (INCIDENT_TYPES is the same list the prompt itself was given,
# so this stays in sync with prompts/emergency_prompt.py automatically).
_INCIDENT_LOOKUP = {name.lower(): name for name in INCIDENT_TYPES}


def _get_client():
    global _client
    if _client is None:
        from google import genai
        api_key = os.getenv("GEMINI_API_KEY")
        if not api_key:
            raise ValueError("GEMINI_API_KEY not set — only required when Gemini is enabled.")
        _client = genai.Client(api_key=api_key)
    return _client


def analyze_with_gemini(message: str) -> str:
    """
    Analyze an emergency message using Gemini. Only ever called from
    pipeline.py when config.GEMINI_ENABLED is true AND the rule-based
    classifier returned "Unknown" — never on the default critical path.

    Returns the raw response text (see parse_gemini_response() for
    turning this into structured fields). Returns an "Gemini Error: ..."
    string instead of raising on any failure — pipeline.py treats that
    as "Gemini didn't help", not a crash.
    """
    prompt = EMERGENCY_ANALYSIS_PROMPT.format(message=message)
    try:
        client = _get_client()
        response = client.models.generate_content(model=GEMINI_MODEL_NAME, contents=prompt)
        return response.text
    except Exception as e:
        return f"Gemini Error: {e}"


def parse_gemini_response(raw_text: str) -> dict:
    """
    Parses the constrained-format text analyze_with_gemini() returns
    (see prompts/emergency_prompt.py) into fields the pipeline can
    actually act on.

    THE GAP THIS CLOSES: previously, analyze_with_gemini()'s output was
    only ever attached to the API response as an opaque "gemini_note"
    string — the pipeline's actual incident/urgency/priority decision
    was never updated from it, even when Gemini correctly identified
    something the rule engine missed. A message that clearly said "Fire,
    Critical" in gemini_note could still come back with
    incident="Unknown", urgency=1, priority=1.0 in the fields that
    actually drive dispatch. This function is what pipeline.py now uses
    to fix that — see its call site there.

    Returns:
        {
          "incident": str | None,   # one of INCIDENT_TYPES, or None if unparseable/not confidently matched
          "urgency": int | None,    # 1-5, or None if unparseable
          "summary": str | None,
        }
    Never raises — a malformed or unexpected response (e.g. the "Gemini
    Error: ..." string analyze_with_gemini() returns on failure) just
    yields all-None fields, and pipeline.py's existing rule-based result
    is left untouched in that case.
    """
    result = {"incident": None, "urgency": None, "summary": None}
    if not raw_text or raw_text.startswith("Gemini Error:"):
        return result

    incident_match = re.search(r"Incident Type:\s*(.+)", raw_text, re.IGNORECASE)
    if incident_match:
        candidate = incident_match.group(1).strip().rstrip(".")
        result["incident"] = _INCIDENT_LOOKUP.get(candidate.lower())

    severity_match = re.search(r"Severity:\s*(.+)", raw_text, re.IGNORECASE)
    if severity_match:
        candidate = severity_match.group(1).strip().rstrip(".").lower()
        result["urgency"] = _SEVERITY_TO_URGENCY.get(candidate)

    summary_match = re.search(r"Short Summary:\s*(.+)", raw_text, re.IGNORECASE)
    if summary_match:
        result["summary"] = summary_match.group(1).strip()

    return result
