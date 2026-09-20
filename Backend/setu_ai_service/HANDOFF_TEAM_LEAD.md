# SETU AI Service — Handoff to Team Lead (Vaibhav)

This covers what this service is, what changed in this review pass, and
what needs a team decision before integration. For the full technical
architecture, read `ARCHITECTURE.md` inside the service folder — this
doc is the "what do I need to know/decide" summary on top of that.

---

## 1. What this service does, in one paragraph

Vaishnavi's AI service takes a raw distress message (text, or now voice
— see below) and turns it into a structured decision: what kind of
emergency it is, how urgent, whether it's a duplicate of something
already being tracked, and a plain-English explanation of why. It's
rule-based first (fast, offline, predictable) with Gemini only as a
narrow fallback for messages the rules genuinely can't classify — this
matches the mesh's own "can't depend on a live connection" constraint.

## 2. What I found and fixed in this pass

No feature was removed — everything below is a fix or an addition.

- **The Gemini fallback wasn't actually doing anything.** When the rule
  engine returned "Unknown" and Gemini was consulted, Gemini's answer
  was only ever attached as a raw text note — the actual
  `incident`/`urgency`/`priority` fields stayed "Unknown"/1/1.0 even
  when Gemini correctly identified the emergency. Fixed: the fallback
  now parses Gemini's response and applies it. See
  `ARCHITECTURE.md` section 4 for the details.
- **One missing keyword.** "asurakshit" (Hinglish for "unsafe") wasn't
  in the Women Safety keyword lists — found via the evaluation script,
  which had one core-set miss because of it. Fixed; core-set accuracy
  went from 98.2% to 100%.
- **A missing dependency.** `requirements.txt` was missing
  `scikit-learn`, which the evaluation script needs — a fresh
  `pip install -r requirements.txt` would have left `python -m
  models.read_data` broken. Fixed.
- **Docs were out of date.** `ARCHITECTURE.md` said "no voice input
  yet" — voice input is actually implemented and working
  (`POST /analyze-voice`, Whisper-based). Updated the doc to match the
  code.
- Added regression tests for all of the above (5 new tests, 38/38 pass).

Full test suite + the evaluation script (`python -m models.read_data`)
both run clean. No secrets in this submission — checked source and git
history.

## 3. Decisions that need the team, not just this service

**Duplicate detection may now exist twice.** Ayush's backend already
has its own deduplication logic (packet_id + geo-clustering, in the
backend's `incident_service.py`/`deduplication_service.py`). This
service *also* does duplicate detection — a richer version (geo +
time + lexical + multilingual embedding similarity). Right now these
are two independent systems that don't know about each other. Before
integration, the team needs to decide: does this AI service's dedup
replace the backend's simpler version, run alongside it, or does the
backend only use this service's `is_duplicate`/`matched_cluster_id`
output and drop its own? See the Ayush-specific handoff doc for the
technical detail — this note is here because it's a product decision,
not just a code change.

**Where does this service actually run?** It's a separate FastAPI app
(`app.py`, its own `/analyze` endpoint) — right now nothing calls it
automatically. Two real options:
1. **Run it as its own process**, and have the backend make an HTTP
   call to it from the ingest pipeline.
2. **Import it as a Python library** directly into the backend (since
   both are FastAPI/Python) via `service/ai_service.py`'s
   `analyze_emergency()` function — no network hop, one less service to
   deploy and keep alive during the demo.

Given this is a hackathon deployment, (2) is very likely simpler and
more robust for demo day — no second process to keep running, no
network failure mode between two of your own services. The Ayush
handoff doc below assumes option 2 and shows exactly how.

**Heavy dependencies are optional, on purpose — decide what your demo
machine actually needs.** `sentence-transformers` (multilingual dedup)
and `openai-whisper` (voice) are both soft dependencies: if they're not
installed, the service falls back automatically (lexical-only dedup,
voice endpoint returns a clean error) rather than crashing. If the demo
machine won't reliably have internet to download the ~120MB embedding
model and ~150MB Whisper model on first run, it's safer to either
pre-download them ahead of time or explicitly set
`SETU_AI_EMBEDDING_DEDUP_ENABLED=false` and skip wiring up
`/analyze-voice` for the live demo.

## 4. What's a known, documented limitation (not a bug)

From `ARCHITECTURE.md` — worth knowing before a judge asks:
- Keyword-collision false positives on deliberately ambiguous phrasing
  ("fire safety drill") — a real limitation of keyword matching,
  documented and measured (87.5% false-trigger rate on 8 deliberate
  trap messages), not hidden.
- In-memory duplicate cluster cache — resets on restart, not shared
  across multiple worker processes. Fine for a single-process demo.
- Hinglish (Roman script) only — no Devanagari, no languages beyond
  Hindi.

## 5. Quick way to verify it yourself

```bash
cd setu_ai_service
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
python -m pytest                 # 38 tests, should all pass
python -m models.read_data       # evaluation report against the labeled dataset
uvicorn app:app --reload         # run standalone, hit POST /analyze
```
