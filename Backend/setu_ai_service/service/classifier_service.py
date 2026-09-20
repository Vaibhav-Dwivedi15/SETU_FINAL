"""
SETU AI - Legacy Classifier Service

NOT used by the live pipeline - models/pipeline.py calls
service/gemini_service.py directly, and only when config.GEMINI_ENABLED
is true AND the rule-based classifier returned "Unknown". That is the
one and only path to the Gemini API that should sit anywhere near the
emergency-critical flow.

This module previously called Gemini directly with no gate at all, so
if anything ever imported classify_emergency(), it would silently
bypass the feature flag and make a live API call regardless of
SETU_AI_GEMINI_ENABLED. Fixed here to respect the same flag pipeline.py
does. Kept around (rather than deleted) in case a teammate is already
importing it, but it is not wired into any route.

Author : SETU Team
Version : 2.1 (fixed: was bypassing config.GEMINI_ENABLED entirely)
"""

from config import GEMINI_ENABLED
from service.gemini_service import analyze_with_gemini


def classify_emergency(message: str) -> str:
    """
    Classify an emergency message using Gemini.

    Only actually calls the Gemini API if config.GEMINI_ENABLED is true
    (set SETU_AI_GEMINI_ENABLED=true). Otherwise returns a clear message
    instead of silently skipping the flag.
    """
    if not GEMINI_ENABLED:
        return "Gemini disabled (SETU_AI_GEMINI_ENABLED is not set) - no classification performed."

    return analyze_with_gemini(message)


if __name__ == "__main__":
    result = classify_emergency(
        "Fire in my building and people are trapped."
    )

    print(result)
