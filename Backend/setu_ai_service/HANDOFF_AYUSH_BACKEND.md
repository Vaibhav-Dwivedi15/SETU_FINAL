# SETU AI Service — Integration Handoff for Ayush (Backend Lead)

This is the concrete "how do I wire this in" doc. It assumes you're
calling this as a Python library from within your own FastAPI backend
(not as a separate HTTP service) — see the Team Lead handoff doc for
why that's the recommended option for a hackathon deployment.

---

## 1. Important — read this before wiring anything in

**Your backend already has its own duplicate/clustering logic**
(`incident_service.py` / `deduplication_service.py`, geo+type based).
**This AI service also does duplicate detection** — a more capable
version (geo + time + lexical + multilingual embedding similarity, see
`models/duplicate_detector.py`). Right now these have never run
together, and if you wire both in blindly you'll get two independent,
possibly-disagreeing answers to "is this a duplicate."

**Before you integrate, decide one of:**
- **(A)** Use this service's `is_duplicate` / `matched_cluster_id`
  output as the source of truth, and stop calling your own
  clustering logic for new incident creation.
- **(B)** Keep your own clustering as the source of truth for now, and
  only use this service's `incident` / `urgency` / `priority` /
  `explanation` fields (ignore its `is_duplicate` output entirely).
- **(C)** Run both and log where they disagree, to build confidence
  before cutting over — reasonable if you have time before the demo,
  riskier if you don't.

This doc's example code below treats the AI service as the dedup source
of truth (option A), since it's the more capable implementation — but
this is your and Vaibhav's call, not something to silently decide by
just importing code.

## 2. The one function you need

```python
from service.ai_service import analyze_emergency

result = analyze_emergency(
    message=str,          # required — the packet's message field
    emergency_id=str,     # required — the packet's emergency_id
    relay_count=int,      # default 0 — see field mapping below
    age_seconds=int,      # default 0 — see field mapping below
    latitude=float,       # default 0.0 — matches your packet spec's no-GPS-fix fallback
    longitude=float,      # default 0.0
)
```

Returns a `dict` (same shape as the `/analyze` HTTP endpoint would
return — see `models/response_models.py` for the full field list with
descriptions):

```python
{
  "message": str,
  "emergency_id": str,
  "incident": str,                 # "Fire", "Medical", "Women Safety", "Unknown", etc.
  "incident_confidence": float,    # 0.30-0.95, or 0.60 if Gemini-assisted
  "incident_explanation": str,     # human-readable, safe to show a dispatcher directly
  "urgency": int,                  # 1-5
  "urgency_confidence": float,
  "urgency_explanation": str,
  "priority": float,               # 1.0-5.0, AI-assessed — see field-naming note below
  "is_duplicate": bool,
  "matched_cluster_id": str,       # emergency_id this report is clustered under
  "similarity": float,
  "match_method": str,             # "embedding" | "lexical"
  "distance_meters": float | None,
  "gemini_note": str | None,       # only present if Gemini fallback was used
  "gemini_assisted": bool | None,  # True only if Gemini's answer actually changed incident/urgency
}
```

**Field-naming collision to watch for:** your `PacketIn` schema already
has its own `priority` field (client/sender-declared, "High"/"Medium"
etc. per your emergency packet schema). This service's `priority` is a
*different*, AI-computed float (1.0-5.0). **Do not overwrite one with
the other** — store both, name them distinctly in your `Incident`
model (e.g. `sender_priority` vs `ai_priority`) if you weren't already
planning to.

## 3. Field mapping from your packet schema

| This service wants | Comes from |
|---|---|
| `message` | `PacketIn.message` directly |
| `emergency_id` | `PacketIn.emergency_id` directly |
| `latitude`, `longitude` | `PacketIn.latitude`, `PacketIn.longitude` directly (already share the same 0.0/0.0 no-GPS-fix convention — nothing to translate) |
| `relay_count` | `PacketIn.hop_count` — same concept, different name. Pass it straight through. |
| `age_seconds` | Not a packet field — compute it: `int(time.time() - parse(PacketIn.timestamp).timestamp())` at the point you call this, right after signature verification |

## 4. Suggested call site

In `routers/ingest.py`, inside your packet-processing loop — after
signature verification passes and before you decide whether to create
a new `Incident` or attach to an existing one (i.e., where your own
clustering logic currently runs):

```python
from service.ai_service import analyze_emergency
import time
from datetime import datetime

# ... after signature is verified, packet.type == PacketType.EMERGENCY ...

age_seconds = int(time.time() - datetime.fromisoformat(packet.timestamp).timestamp())

ai_result = analyze_emergency(
    message=packet.message,
    emergency_id=packet.emergency_id,
    relay_count=packet.hop_count,
    age_seconds=max(age_seconds, 0),   # clock skew guard - never pass negative age
    latitude=packet.latitude,
    longitude=packet.longitude,
)

if ai_result["is_duplicate"]:
    # attach to ai_result["matched_cluster_id"] instead of creating a new Incident
    ...
else:
    # create a new Incident; store ai_result["incident"], ai_result["urgency"],
    # ai_result["priority"] (as a separate column from the packet's own priority field),
    # and ai_result["incident_explanation"] / ai_result["urgency_explanation"] if you
    # want to surface "why" on the dashboard
    ...
```

## 5. Dependencies and environment

**If you're merging this into your own `requirements.txt`:** add
`google-genai`, and optionally `sentence-transformers` + `numpy` (for
multilingual dedup) and `openai-whisper` + `python-multipart` (for
voice, if you're also exposing `/analyze-voice` through your API). The
two "optional" groups are soft dependencies — the service degrades
gracefully without them (lexical-only dedup, voice endpoint returns a
clean 422) rather than crashing, so it's safe to skip them on a
resource-constrained demo machine.

**Environment variables** (add to your `.env` alongside your existing
ones):
```
GEMINI_API_KEY=              # only needed if you turn Gemini on
SETU_AI_GEMINI_ENABLED=false # keep off unless you've evaluated its value first
SETU_AI_EMBEDDING_DEDUP_ENABLED=true  # set false if the demo machine has no internet for first-run model download
```

**Python version note:** this service's `requirements.txt` intentionally
leaves versions unpinned — some packages (pydantic-core, numpy) had no
prebuilt wheels for very new Python versions at the time this was
written. If your backend pins exact versions and you're merging
dependency lists, resolve conflicts by relaxing pins rather than
force-installing — check both services still import cleanly after.

## 6. Verifying the integration

```python
# quick smoke test after wiring in
from service.ai_service import analyze_emergency
result = analyze_emergency("Fire in my building", emergency_id="test-1", relay_count=2, age_seconds=10)
assert result["incident"] == "Fire"
assert result["urgency"] == 5
print(result)
```

If this runs inside your existing backend's Python environment without
import errors, the integration is wired correctly.
