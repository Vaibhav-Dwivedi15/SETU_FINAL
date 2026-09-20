# SETU Backend — Handoff for Ayush (next chat session)

Deployed at: **https://setu-backend-cy78.onrender.com**

This session did three things: (1) implemented real Ed25519 signature
verification, (2) integrated Vaishnavi's AI service as a library, then
reversed one part of that decision, and (3) added a dashboard resolve
endpoint. Below is everything the next session needs to pick up
cleanly.

---

## 1. Signature verification — DONE, implemented for real

`app/services/signature_service.py` was a stub (`always True`) at the
start of this session. Now does real Ed25519 verification:

- `sender_id` = hex-encoded Ed25519 public key (self-certifying, no
  registry lookup needed for verification itself).
- Signed payload: pipe-separated (`"|".join(...)`), common fields
  (`packet_id|sender_id|type|timestamp|nonce`) + type-specific fields.
- `ttl`, `hop_count`, `protocol_version` are deliberately **excluded**
  from the signed payload (they mutate per relay hop; signing them
  would break verification on any packet past hop 0). Verified this
  directly in the actual file this session (`grep` for
  `"|".join(fields)` and for `ttl`/`hop_count` — confirmed correct,
  pipe separator, exclusions documented in the docstring).
- **Still needs**: a real golden test vector from Vaibhav's next
  multi-hop hardware test (full untruncated packet + signature) to
  prove cross-language (Dart↔Python) byte-exact compatibility. Current
  tests only prove internal Python self-consistency.
- **Action item for next session**: confirm via
  `grep -n "join(fields)" app\services\signature_service.py` that the
  live repo file matches — this was asked for but not yet confirmed by
  Ayush before this handoff was written (ran out of session time).

Also fixed in this session: `tests/test_ingest.py`'s fixtures used fake
`sender_id`/`signature` strings that would fail now that verification
is real — rewritten to generate genuine Ed25519 keypairs per test.

---

## 2. AI service (Vaishnavi's `setu_ai_service`) — integrated as a library

Vendored at `Backend/setu_ai_service/` (sibling of `Backend/app/`, not
inside it — keeps her code separable for future updates).

**The real gotcha, if this ever needs debugging again**: every file
inside `setu_ai_service` uses bare absolute imports (`from models.pipeline
import ...`) assuming ITS OWN folder is the sys.path root. Importing it
normally crashes with `ModuleNotFoundError: No module named 'models'`.
Fixed via `app/utils/setu_ai_import_guard.py`, which adds
`setu_ai_service/`'s path to `sys.path` once at import time. Checked for
naming collisions against this backend's own `app.*`-namespaced modules
— none exist.

`app/services/ai_analysis_service.py` wraps `analyze_emergency()` —
never raises, returns `None` on any AI-side failure (missing deps,
Gemini timeout, etc.) so a broken AI call can never block packet
ingestion.

### Dedup decision — REVERSED mid-session, this is important

- **First decision**: keep this backend's own DB-backed dedup
  (`find_matching_incident` in `incident_service.py`/
  `deduplication_service.py`) as source of truth, ignore the AI
  service's `is_duplicate`/`matched_cluster_id` entirely. Reasoning:
  own dedup was load-tested (5/5 clean runs, 50 concurrent); AI dedup
  was unproven in this pipeline.
- **Reversed per Vaibhav's team direction**: AI service's
  `is_duplicate`/`matched_cluster_id` is now the source of truth.
  `find_matching_incident()` is kept ONLY as a fallback for when
  `ai_result` is `None` (AI call failed) — never both at once.
- **Known operational risk, accepted for now**: `duplicate_detector.py`
  keeps cluster state in a plain in-memory Python list (confirmed by
  reading the file directly — the AI team's own code comment says so).
  Resets on server restart; won't stay consistent across multiple
  worker processes. Fine for a single-instance demo; needs Redis or a
  DB-backed store before anything longer-lived.
- **`SETU_AI_EMBEDDING_DEDUP_ENABLED` must be `true`** for this swap to
  actually be an upgrade — without it, it's lexical+geo+time only,
  which isn't meaningfully richer than what it replaced, just less
  durable. This was flipped true as part of this decision.

`matched_cluster_id` is an `emergency_id`, not an incident id — resolved
to an actual `Incident` row via a new helper,
`_find_incident_by_emergency_id()` in `incident_service.py`.

---

## 3. New Incident model fields

`app/models/incident.py` — replaced unused placeholder columns
(`ai_confidence`/`ai_summary`/`ai_urgency` as String) with real ones
matching the AI service's actual output shape:

- `sender_priority` (String) — from the packet's own declared
  `priority` field. Kept deliberately separate from AI fields below —
  the two answer different questions, never conflated.
- `ai_incident_type`, `ai_incident_confidence`, `ai_incident_explanation`
- `ai_urgency` (Integer, 1–5), `ai_urgency_confidence`,
  `ai_urgency_explanation`
- `ai_priority` (Float, 1.0–5.0) — AI-computed, distinct from
  `sender_priority`.

**This was a schema change.** No Alembic migrations exist yet
(`init_db.py`'s `create_all()` only adds missing tables, never alters
existing ones) — required a manual drop+recreate. A script for this,
`drop_and_recreate_incident_tables.py`, was created this session and
already run successfully once against the real Neon DB.

**Known gap, not yet decided**: AI fields are only set once, at initial
incident creation — a later corroborating packet that merges in does
NOT re-run analysis or update these fields (e.g. urgency escalation on
worse follow-up reports isn't reflected). Documented as an open
question in `incident_service.py`'s `create_incident_from_packet`
docstring, not silently decided either way.

---

## 4. New endpoint: `POST /incidents/{id}/resolve`

Dashboard "Mark Resolved" support (item #3 of the integration
decisions doc). Added in `app/routers/incidents.py`, backed by
`resolve_incident_by_id()` in `incident_service.py`.

- Auth: same `X-API-Key` header / `RESPONDER_API_KEY` as every other
  dashboard route. No new key introduced.
- Parallel path alongside the mesh-native signed-termination flow
  (`POST /ingest`, `type=termination`) — does not replace or touch it.
  Exists because a private Ed25519 signing key can't live in a browser.
- Idempotent: resolving an already-CLOSED incident returns 200
  unchanged, not an error. 404 only if `incident_id` doesn't exist.
- Confirmed unchanged: `/ingest` and `/responders/keys` request/response
  shapes — only internal dedup logic changed inside `/ingest`'s
  handler, never its contract.

---

## 5. Environment variables (current full state)

```
APP_NAME=
APP_VERSION=
DEBUG=
DATABASE_URL=
RESPONDER_API_KEY=

GEMINI_API_KEY=                              # blank, only needed if Gemini ever turns on
SETU_AI_GEMINI_ENABLED=false                 # staying off -- unevaluated, extra failure mode on critical path
SETU_AI_EMBEDDING_DEDUP_ENABLED=true          # flipped from false -- required for AI dedup swap above
```

---

## 6. requirements.txt — current full state

Real pinned freeze (Python 3.13, from Ayush's machine) plus additions
made this session:

```
alembic==1.18.5
annotated-doc==0.0.5
annotated-types==0.8.0
anyio==4.14.2
certifi==2026.7.22
cffi==2.1.0
charset-normalizer==3.4.9
click==8.4.2
colorama==0.4.6
cryptography==50.0.0
fastapi==0.141.1
greenlet==3.5.4
h11==0.16.0
httpcore==1.0.9
httptools==0.8.0
httpx==0.28.1
idna==3.18
iniconfig==2.3.0
Mako==1.3.12
MarkupSafe==3.0.3
packaging==26.2
pluggy==1.6.0
psycopg2-binary==2.9.12
pycparser==3.0
pydantic==2.13.4
pydantic-settings==2.14.2
pydantic_core==2.46.4
Pygments==2.20.0
pytest==9.1.1
python-dotenv==1.2.2
PyYAML==6.0.3
requests==2.34.2
SQLAlchemy==2.0.51
starlette==1.3.1
typing-inspection==0.4.2
typing_extensions==4.16.0
urllib3==2.7.0
uvicorn==0.52.0
watchfiles==1.2.0
websockets==17.0

# --- setu_ai_service embedding dedup (now in use) ---
sentence-transformers
numpy

# --- setu_ai_service Gemini path -- still NOT needed ---
# google-genai       -- only if SETU_AI_GEMINI_ENABLED=true
```

`cryptography` was added earlier this session for signature
verification. `sentence-transformers`/`numpy` added for the dedup
swap, left unpinned deliberately — matches the AI team's own
convention (exact pins caused build failures for them on newer Python,
no prebuilt wheels yet for some transitive deps).

---

## 7. Files touched this session (full replacements given, not diffs)

- `app/services/signature_service.py` — real Ed25519 implementation
- `app/models/incident.py` — new fields (see #3)
- `app/services/incident_service.py` — AI integration + dedup swap +
  resolve endpoint support + Postgres dialect guard (see #8)
- `app/services/ai_analysis_service.py` — new, AI service wrapper
- `app/utils/setu_ai_import_guard.py` — new, sys.path fix
- `app/routers/ingest.py` — AI analysis call site, updated docstrings
- `app/routers/incidents.py` — new resolve endpoint
- `tests/test_signature_service.py` — new, unit tests for signing/verification
- `tests/test_ingest.py` — rewritten fixtures to use real Ed25519 signing
- `requirements.txt`, `.env` — see #5, #6
- `drop_and_recreate_incident_tables.py` — new, one-off DB reset script (already run once)
- `send_test_packet.py` — new, live end-to-end smoke test script

---

## 8. Other fix found and applied this session (unrelated to AI/signing)

`incident_service.py`'s `handle_sos_packet` used
`SELECT pg_advisory_xact_lock(...)` (added Aug 2 for a real concurrency
race-condition fix under load) — Postgres-only, and the local test
suite runs against SQLite, which doesn't have that function. This was
silently broken for local `pytest` runs since Aug 2 and nobody had
re-run the suite until this session. Fixed with a dialect check:
```python
if db.get_bind().dialect.name == "postgresql":
    db.execute(text("SELECT pg_advisory_xact_lock(:key)"), {"key": lock_key})
```
Real Postgres deployments keep full protection; SQLite-based tests skip
it harmlessly. Documented tradeoff: the race condition this lock
prevents is untested on SQLite as a result — only ever verified against
real Postgres.

---

## 9. STILL PENDING — top of next session's list

1. **Confirm `pytest -q` is green** with all of this session's changes
   applied (dedup swap + resolve endpoint + earlier signature/AI
   fixes). Last confirmed run before these final two changes was
   `66 passed` after fixing the SQLite dialect issue and the
   `ai_result` kwarg mismatch — but the dedup-swap and resolve-endpoint
   changes have NOT been test-confirmed yet as of this handoff.
2. **Confirm signature_service.py fix is live in the real repo** — run
   `grep -n "join(fields)" app\services\signature_service.py` and
   confirm it shows `"|".join(fields)`. This was verified correct in
   what was delivered this session, but not yet independently
   re-confirmed by Ayush in his actual working copy.
3. **Golden test vector** — next multi-hop hardware test (3rd device),
   capture one full untruncated signed packet + signature from
   Vaibhav's side, verify against this backend's real
   `verify_signature()`.
4. Vaibhav has already confirmed items #2 and #3 (dedup swap + resolve
   endpoint) as approved and considers mobile/mesh/backend fully wired
   to the same URL/contract — backend is "done for MARK I" pending
   only the pytest confirmation above.

---

## 10. Quick reference — how things are organized

- Real backend: `https://setu-backend-cy78.onrender.com`
- DB: Neon Postgres (Singapore, pooled endpoint required for concurrent load)
- Ayush's terminal: **cmd.exe**, not PowerShell (`set VAR=value`,
  `copy`/`move`, `&&` chaining)
- Team preference: full-file replacements only (no diffs/snippets),
  inline code blocks by default (not downloadable files) unless the
  change is substantial/schema-related/needs verification first
