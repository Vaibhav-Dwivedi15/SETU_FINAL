"""
SETU AI - Centralized Configuration

Single place for tunable settings that were previously scattered as
magic numbers across duplicate_detector.py and gemini_service.py.
"""

import os

# --- Duplicate detection ---
SIMILARITY_THRESHOLD = 0.75
TIME_WINDOW_SECONDS = 300

# --- Gemini (optional enhancement layer, NOT the primary path) ---
# OFF by default: the rule-based pipeline must always be able to produce
# a result on its own, with no dependency on an external API call, since
# this sits on the emergency-critical path. Turn on only after Gemini's
# added value (catching ambiguous "Unknown" incidents the keyword rules
# miss) has actually been evaluated — set env var SETU_AI_GEMINI_ENABLED=true.
GEMINI_ENABLED = os.getenv("SETU_AI_GEMINI_ENABLED", "false").lower() == "true"
GEMINI_MODEL_NAME = "gemini-2.0-flash"
