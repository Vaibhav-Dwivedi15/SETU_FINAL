"""
SETU AI - Centralized Configuration

Single place for tunable settings that were previously scattered as
magic numbers across duplicate_detector.py and gemini_service.py.
"""

import os

# --- Duplicate detection ---
SIMILARITY_THRESHOLD = 0.75
TIME_WINDOW_SECONDS = 300

# Two similar-text reports are only merged into one incident if they're
# also within this radius of each other. Without this, "help fire" from
# two different buildings would wrongly get merged just because the text
# is similar. 500m is a rough "same block/building cluster" radius for a
# demo - tune based on real GPS accuracy once field-tested.
GEO_DEDUP_RADIUS_METERS = 500

# When either message's GPS reads (0.0, 0.0) - the documented fallback
# used when GPS is unavailable (see packet spec, Section 3 of the
# project handoff) - location can't be trusted, so dedup falls back to
# text+time only rather than wrongly rejecting a real duplicate just
# because one device had no GPS fix.

# --- Embedding-based similarity (multilingual, catches Hinglish/English
# paraphrases that lexical/difflib similarity misses - e.g. "Fire in
# Block A" vs "aag lag gayi Block A mein" share no real character
# overlap but are the same incident) ---
# ON by default, but this is a soft dependency: if sentence-transformers
# isn't installed, or the model can't be downloaded on first run (no
# internet), duplicate_detector.py catches that and falls back to the
# plain lexical (difflib) similarity automatically - it never crashes
# the service either way. Set SETU_AI_EMBEDDING_DEDUP_ENABLED=false to
# force lexical-only (e.g. for a fully offline demo where the model
# was never downloaded/cached).
EMBEDDING_DEDUP_ENABLED = os.getenv("SETU_AI_EMBEDDING_DEDUP_ENABLED", "true").lower() == "true"
EMBEDDING_MODEL_NAME = "paraphrase-multilingual-MiniLM-L12-v2"
# Cosine similarity threshold for the embedding model. NOT the same
# scale as SIMILARITY_THRESHOLD (difflib character-overlap ratio) -
# multilingual sentence embeddings tend to sit higher for "same topic"
# text, so this is a separate, untuned starting point. Retune this
# against real labeled pairs (see notebooks/evaluation.ipynb in the
# original role brief) once you have enough data to check precision.
EMBEDDING_SIMILARITY_THRESHOLD = 0.30  # provisional: tuned from 3 real samples on 2026-08-02 (0.428, 0.331 same-incident; 0.210 unrelated). Still a small sample -- retune with more real Hinglish pairs once you have labeled data.

# --- Gemini (optional enhancement layer, NOT the primary path) ---
# OFF by default: the rule-based pipeline must always be able to produce
# a result on its own, with no dependency on an external API call, since
# this sits on the emergency-critical path. Turn on only after Gemini's
# added value (catching ambiguous "Unknown" incidents the keyword rules
# miss) has actually been evaluated - set env var SETU_AI_GEMINI_ENABLED=true.
GEMINI_ENABLED = os.getenv("SETU_AI_GEMINI_ENABLED", "false").lower() == "true"
GEMINI_MODEL_NAME = "gemini-2.0-flash"

# Fixed confidence value used when Gemini's fallback classification is
# applied (see models/pipeline.py). This is deliberately NOT computed
# the way models/confidence_scorer.py scores rule-engine matches (match
# count, category conflicts) - there's no equivalent signal available
# from an LLM's free-text response. 0.60 signals "a real classification
# happened, not a guess" without claiming the same kind of evidence-based
# confidence a 3-keyword rule match earns.
GEMINI_CONFIDENCE = 0.60
