# SETU — Full Debug & Analysis Report
**Date:** August 4, 2026
**Scope:** Backend (`Backend_final.zip`), AI Service (`setu_ai_service_reviewed.zip`), Dashboard (`setu_dashboard_reviewed.zip`), Mobile App (`setu_app.zip`), SOS App (`setu_sos_.zip`)
**Method:** Static review, dependency install + actual test execution where possible, cross-zip diffing, secret scanning. Flutter apps reviewed statically only — this sandbox has no network access to pub.dev, so `flutter pub get`/`flutter test`/`flutter build` could not be run.

---

## TL;DR — what needs attention before submission

| Priority | Finding | Component |
|---|---|---|
| 🔴 High | `setu_sos_app` is missing the entire mesh + security layer present in `setu_app` | Mobile |
| 🔴 High | Backend zip has **no CORS middleware anywhere in the code** — but the live Render deploy is working with `CORS_ALLOWED_ORIGINS_RAW` set. These two facts don't match. | Backend |
| 🟡 Medium | Real, reproducible test failure: incident dedup breaks when tests run as a suite (not in isolation) | Backend |
| 🟡 Medium | Both Flutter zips ship `build/` and `.dart_tool/` (1.3GB + 760MB) — shouldn't be in source zips | Mobile / SOS |
| 🟢 Low | No secrets, no live `.env` files found in any of the 5 zips | All |
| 🟢 Low | Dashboard and vendored AI service are byte-identical to already-deployed/already-reviewed copies | Dashboard, AI |

---

## 1. Backend (`Backend_final.zip`)

### 1.1 Security — clean
No live `.env`, no hardcoded API keys, no committed secrets anywhere in the zip. `.gitignore` correctly excludes `.env`. `.env.example` documents all required vars (`DATABASE_URL`, `RESPONDER_API_KEY`, `GEMINI_API_KEY`, etc.) with blank placeholders — correct practice.

### 1.2 🔴 CORS discrepancy — needs a direct check with Ayush
Searched the entire codebase (`grep -rin "cors"`) — **zero results**. No `CORSMiddleware` import, no CORS-related config field in `app/core/config.py`'s `Settings` class. If `CORS_ALLOWED_ORIGINS_RAW` were set as an env var against *this exact code*, it would be silently ignored (`Settings` has `extra="ignore"`).

This conflicts with what we just did in the dashboard deploy chat: we added `CORS_ALLOWED_ORIGINS_RAW` on Render and the dashboard came up "Live (Backend Connected)."

**Most likely explanation:** Ayush's live Render deployment is pulling from a GitHub repo (`ShadowGeek2006/Setu-backend`, confirmed from the Render dashboard screenshot in the deploy chat) that has newer commits than this zip — i.e. **this zip is stale relative to production.**

**Action needed:** Confirm with Ayush that this zip reflects the current `main` branch. If not, get a fresh export before using this zip as the basis for any further backend work or handoff documentation. Don't assume the CORS code exists just because it's working live — verify.

### 1.3 🟡 Real, reproducible test failure
Full suite: **27/28 pass.** The failure — `test_nearby_same_type_reports_merge_into_one_incident` — is **not** flaky-by-chance; it fails deterministically whenever it runs after other tests in the same file/session, and passes 100% of the time in isolation.

**Root cause, confirmed by reading the code and tracing logs:**
- Dedup logic was intentionally changed (per in-code comments: "decision REVERSED since Day 5/6") so the AI service's `is_duplicate`/`matched_cluster_id` is now the *primary* source of truth for merging incidents, not the backend's own `find_matching_incident()` (haversine distance + time window). The backend's own dedup is now only a fallback for when the AI call fails.
- The AI service's duplicate detector (`setu_ai_service/models/duplicate_detector.py`) keeps its cluster state in a **plain in-memory Python list** at module scope. This is already flagged in the code's own comments as a known operational risk ("resets on restart, not consistent across multiple workers").
- That same in-memory state is what causes the test failure: earlier tests in the same pytest session leave residual cluster state that this test then collides with, causing an incorrect duplicate/non-duplicate determination.

**This is a legitimate, load-bearing bug for the actual demo**, not just a test-suite quirk — if the backend process handling live traffic during a demo has any state from earlier packets, later "genuinely new" reports could incorrectly merge into old incidents, or corroborating reports could fail to merge and needlessly create duplicate incidents. Given the code comments already acknowledge this is architecturally risky beyond a single-instance demo, it's worth deciding explicitly:
- Is a single, long-running backend process (not restarted between test packets) acceptable for the demo? If so, this specific test failure is cosmetic (test isolation only) and not a live risk **as long as no other traffic hits the same instance during a demo run.**
- If the judges' demo involves multiple test rounds without a backend restart in between, this in-memory state could cause visibly wrong incident merging on stage. Worth a dry run exactly mimicking demo conditions (multiple SOS submissions, no restart) before SIH judging.

### 1.4 Other observations
- Several loose `debug_test*.py` and `debug_*.py` scripts sit in the repo root (not in `tests/`). Harmless, but worth cleaning out of anything that gets submitted/shown to judges — reads as unfinished/messy.
- `drop_and_recreate_incident_tables.py` is a genuinely destructive script (drops `incidents`, `raw_packets`, `incident_audit_log` tables). It's well-documented with an explicit warning docstring, which is good practice — just flagging that it exists at the repo root where it's easy to run by accident. Consider moving it to a `scripts/` or `migrations/` folder.
- `main.py`'s own docstring already flags that `init_db()`'s `create_all()` (used in place of real Alembic migrations) only adds missing tables and never alters existing ones — acknowledged tech debt, not something broken right now.
- Deprecation warnings from Pydantic v2 (`class Config` → `ConfigDict`) across 4 schema files — cosmetic, not functional.

---

## 2. AI Service (`setu_ai_service_reviewed.zip`)

### 2.1 Consistency check — passed
Diffed byte-for-byte against the copy vendored inside `Backend_final.zip`'s `setu_ai_service/` folder: **identical, zero differences.** No version drift between the standalone submission and what's embedded in the backend.

### 2.2 Test results — clean
Ran the AI service's own test suite in isolation (not through the backend): **38/38 pass.** This confirms the AI service's internal logic (classification, priority adjustment, confidence scoring, dedup detector itself) is correct on its own terms — the backend-level dedup failure above is about *cross-process/cross-request state*, not a bug in this service's logic.

### 2.3 Notable, already-documented risk
`embedding_similarity.py` needs to download `sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2` from Hugging Face on first run. In this sandboxed environment (no internet to huggingface.co), it correctly fails soft and falls back to lexical (`difflib`) similarity only, exactly as designed — confirmed by the log output. **Real-world implication:** whichever machine actually runs this in production/demo needs internet access on first boot to pull that model, or `SETU_AI_EMBEDDING_DEDUP_ENABLED` should explicitly be set to `false` to avoid relying on a partially-degraded similarity check without realizing it. Worth explicitly confirming Render's backend has successfully downloaded this model at least once (check backend logs for the "Embedding model unavailable" warning — if it's present in production logs, dedup is running in degraded lexical-only mode).

---

## 3. Dashboard (`setu_dashboard_reviewed.zip`)

Diffed against the copy already deployed to `https://setu-sih-dashboard.vercel.app` in the deploy chat: **identical, zero differences.** Already fully verified (`npm install && npm run build` clean, deployed, CORS confirmed working, showing "Live" against the real backend). Nothing further needed here — this component is genuinely done.

---

## 4. Mobile App (`setu_app.zip`)

### 4.1 Structure — this is the complete, current app
124 Dart files. Full mesh layer (`lib/mesh/`: `MeshService`, `LocalQueueService`, `ResponderRegistry`, `UploadScheduler`, `IdentityService`, etc.), full security layer (`lib/security/`: `SigningService`, `PacketValidator`, `ReplayProtectionService`, `NonceCache`, `TimestampValidator`), and the native Kotlin transport layer under `android/app/src/main/kotlin/com/setu/mesh/` (`NearbyConnectionsManager.kt`, `PacketRelayEngine.kt`, `MeshForegroundService.kt`) — all present and consistent with the architecture documented in `notes/System_Architecture.md`.

### 4.2 `mesh_service.dart` integrity — confirmed fixed
This is the exact file that was previously found completely overwritten with an unrelated class (a critical bug caught earlier in the project). In this zip it's correct: 294 lines, proper imports (`packet_validator`, `security_constants`, `backend_service`, `local_queue_service`, `mesh_metrics`, `mesh_policy`, `nearby_service`, `responder_registry`), consistent with what a packet relay engine should actually contain. **No longer an issue in this submission.**

### 4.3 Secrets/hardcoded values
`backend_service.dart` has the production backend URL (`https://setu-backend-cy78.onrender.com`) hardcoded as a default constructor parameter — this is a public URL, not a secret, so no security issue. Worth noting only as a minor "should probably be build-config-driven eventually" item, not urgent for a hackathon submission. No hardcoded API keys, IPs, or other secrets found anywhere in `lib/`.

### 4.4 Build/test status
Could not run `flutter pub get` / `flutter analyze` / `flutter test` in this sandbox — no network route to pub.dev is allowlisted here. This needs to be verified on a machine with Flutter + internet access. If that hasn't been done recently against *this exact zip*, it's worth doing before relying on this as "known good."

### 4.5 Housekeeping
The zip included `build/` (1.3GB) and `.dart_tool/` (192MB) — these are regenerated automatically by Flutter and should never be committed or shipped in a submission zip. Worth checking `.gitignore` actually excludes them (Flutter's default template does, but worth confirming nothing overrode it) and re-exporting a clean zip if this goes to judges or a new chat.

---

## 5. SOS App (`setu_sos_.zip`)

### 5.1 🔴 Missing mesh + security layers — needs clarification, not just cleanup
This is the most important finding in the whole review. `setu_sos_app`'s `lib/` folder has **88 Dart files** with the same high-level `features/`, `core/`, `config/`, `routes/` structure as `setu_app` — but **no `lib/mesh/` folder and no `lib/security/` folder at all.** It has no `HANDOFF_*.md`, no architecture notes, and its `README.md` is still the untouched default Flutter template ("A new Flutter project... This is a starting point").

Compared side-by-side, this looks like either:
- An earlier fork of the app, made before the mesh/security integration work happened, that's been kept around and is now stale, or
- A deliberately separate, UI-only variant (e.g. for isolated screen/design work) that was never meant to carry the mesh layer

**Either way, this needs a direct answer, not a guess:** is `setu_sos_app` meant to be submitted/demoed at all? If the intended deliverable is one app, `setu_app` is unambiguously the complete one — it has everything `setu_sos_app` has (same feature folders: `stealth`, `sos`, `lost_child`, `child_safety`, `nearby`, `community`, etc.) *plus* the entire mesh + security core. Submitting or demoing `setu_sos_app` in its current state would mean demoing a version of the app that **cannot actually do mesh relay or packet signing** — silently missing the core mechanism of the whole project.

**Recommended action:** Confirm with whoever owns this zip (Sudheer, per project role assignments) whether `setu_sos_app` is dead/superseded and can be dropped from anything going forward, or whether it's tracking something specific that needs to be merged back into `setu_app` before submission.

### 5.2 Same housekeeping note as 4.5
`build/` (760MB) and `.dart_tool/` (63MB) were also committed in this zip.

---

## 6. Cross-cutting notes

- **No secrets found anywhere** across all 5 zips — a real positive, especially given this project has previously caught a live Gemini key exposure. Whatever process is now in place before zips get shared clearly worked this round.
- **Dashboard and AI service are both confirmed consistent** with previously-reviewed/deployed copies — no silent drift.
- **The backend zip is the one piece of genuine uncertainty** — the CORS mismatch means this specific zip should not be treated as "what's currently live" without Ayush confirming it.
- **The critical unresolved issue from project memory — full signed-packet end-to-end relay between two physical devices was never observed — was not something this review could test** (no physical devices, no live mesh radios in this sandbox). This review does not close that gap; it remains open and should still be treated as untested in any pitch/documentation claims.

