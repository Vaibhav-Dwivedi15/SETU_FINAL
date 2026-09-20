# SETU Security Scorecard

Status only — deliberately no numeric/letter score (an arbitrary score
invites false confidence). Statuses: **IMPLEMENTED**, **PARTIALLY
IMPLEMENTED**, **NOT IMPLEMENTED**, **NOT APPLICABLE**, **NOT VERIFIED**.

## Cryptographic identity & mesh protocol

| Control | Status | Notes |
|---|---|---|
| Ed25519 packet signing/verification | IMPLEMENTED | Real implementation, confirmed by reading `signature_service.py` directly |
| Replay protection (nonce + timestamp + clock skew) | IMPLEMENTED | Pre-existing, unchanged |
| TTL/hop bounds | IMPLEMENTED | Pre-existing (`maxTTL=5`), unchanged |
| Packet size bounds (mesh-side) | IMPLEMENTED | Pre-existing (`SecurityConstants.maxPacketSize=4096`), unchanged |
| Duplicate-storm suppression | IMPLEMENTED | Added prior sprint (jittered suppression, echo tracking) |
| Priority-aware relay queue (anti-starvation) | IMPLEMENTED | Added prior sprint |
| Termination-authorization via responder public-key list | IMPLEMENTED | Pre-existing; fails open with a warning if the list can't sync (existing, documented trade-off) |

## Backend API

| Control | Status | Notes |
|---|---|---|
| Responder API key check | IMPLEMENTED | Pre-existing; comparison hardened to `hmac.compare_digest` this sprint |
| Default-key fail-fast on boot | IMPLEMENTED (this sprint) | Refuses to start in non-debug mode with the placeholder key |
| CORS origin allow-list | IMPLEMENTED | Pre-existing, verified correct (not wildcard) |
| CORS method/header allow-list narrowing | NOT IMPLEMENTED | Left as `*`/`*` — unverifiable against the live dashboard in this sandbox; flagged, not changed |
| Input length/range bounds on `/ingest` fields | IMPLEMENTED (this sprint) | `PacketIn` — every field now bounded |
| Input length/range bounds on `/register` fields | IMPLEMENTED (this sprint) | `RegisterIn` — every field now bounded (was unbounded free text) |
| Proof-of-possession on `POST /register`'s `sender_id` | **NOT IMPLEMENTED** | `sender_id` is a public value (a device's Ed25519 public key, observable in every mesh packet); nothing currently proves the caller holds the matching private key, so a citizen's profile (incl. `medical_history`/`emergency_contacts`) can be overwritten by anyone who knows their `sender_id`. Fix is architecturally sound (reuse `signature_service.py`) but needs a coordinated `setu_app` `ProfileSyncService` change not safely shippable as an untested backend-only pass. **Second-highest-priority follow-up.** |
| Batch size cap on `/ingest/batch` | IMPLEMENTED (this sprint) | `PacketBatchIn.packets`, max 500 |
| Rate limiting — auth routes | IMPLEMENTED (this sprint) | 10 req/5min/IP |
| Rate limiting — responder-action writes | IMPLEMENTED (this sprint) | 20 req/min/IP |
| Rate limiting — public write (`/alerts/{id}/respond`) | IMPLEMENTED (this sprint) | 30 req/min/IP |
| Rate limiting — `/ingest`, `/register`, `/alerts/nearby` | NOT IMPLEMENTED — deliberate | Brief explicitly requires emergency ingestion not be broken by a blanket limiter; existing crypto/field-bound checks are the mitigation instead |
| Global request body-size guard | IMPLEMENTED (this sprint) | 413 above 30MB, all routes |
| SQL injection defenses | IMPLEMENTED | ORM used throughout; the one raw-SQL call (`pg_advisory_xact_lock`) is parameterized, verified by reading it directly |
| Command injection surface | NOT APPLICABLE | No `subprocess`/`os.system`/`shell=True`/`eval`/`exec` found anywhere in `Backend/app` (grepped) |
| SSRF surface | NOT APPLICABLE | Only outbound HTTP call found (`sms_service.py`) targets a hardcoded URL constant, never user input |
| Secret logging | IMPLEMENTED (verified, not changed) | Grepped all logger/print calls for password/secret/key/token/signature — no matches |
| Stack-trace/error leakage | IMPLEMENTED (verified, not changed) | Spot-checked routers raise `HTTPException` with fixed `detail` strings, never `str(exc)` |
| Secrets in source/version control | IMPLEMENTED (verified) | `.env` files present on disk but confirmed **NOT** tracked by git (`.gitignore` covers them, `git ls-files` confirms zero tracked `.env` files); no hardcoded secret-shaped literals found in source by grep |

## Web dashboard

| Control | Status | Notes |
|---|---|---|
| XSS via `dangerouslySetInnerHTML` | IMPLEMENTED (verified, not changed) | Zero matches, grepped `setu_dashboard/src` |
| Token/key storage | PARTIALLY IMPLEMENTED | `X-API-Key` is build-time-embedded in the JS bundle, not `localStorage` — avoids one class of theft (JS-based exfiltration of a stored token) but the key is still extractable from the shipped bundle itself, which is an inherent limitation of this auth model, not a bug this sprint can fix |
| CSRF | NOT APPLICABLE | Header-based auth (`X-API-Key`), not cookies — a cross-site request can't attach the key |
| Content-Security-Policy header | PARTIALLY IMPLEMENTED (this sprint) | A real HTTP-header CSP needs the hosting/CDN layer (no visibility into that here). Added a `<meta http-equiv="Content-Security-Policy">` in `index.html` instead — weaker than a header (strippable if the surrounding HTML itself could be tampered with) but real defense-in-depth against XSS payload capability today. Origins allowed are exactly what the app uses (CARTO tiles, GitHub/unpkg marker icons, Google Fonts, the backend API) — not a wildcard. **Not verified against a running `npm run dev`/`npm run build`** (no Node/npm in this sandbox) — the comment above the meta tag flags a real risk that Vite's dev-mode HMR may need loosening this policy for local development. |
| Source maps in production build | NOT VERIFIED | Vite defaults to no source maps unless explicitly enabled in `vite.config.js`; this project's config does not enable them, but the actual deployed build artifact was not inspected (no build tooling available in this sandbox) |

## Mobile app (Android)

| Control | Status | Notes |
|---|---|---|
| Exported component review | IMPLEMENTED (verified) | Only `MainActivity` is `exported=true` (required — it's the launcher); `MeshForegroundService` is `exported=false`; no broadcast receivers/content providers declared |
| Cleartext traffic | IMPLEMENTED (verified) | No `usesCleartextTraffic="true"`, no custom network security config found; all backend base URLs in Dart source are `https://` |
| TLS certificate pinning | NOT IMPLEMENTED | Standard platform TLS trust store only; not attempted this sprint (would need a real device/build to verify without breaking connectivity) |
| Release build signing | **WAS NOT IMPLEMENTED, PARTIALLY IMPLEMENTED (this sprint)** | **FOUND**: `android/app/build.gradle.kts` unconditionally signed release builds with the shared Flutter **debug** keystore — not a real release signature, and something Google Play itself would reject. Fixed by wiring a real `signingConfigs.release` sourced from a gitignored `android/key.properties` (template: `android/key.properties.example`, no real secret in it) when present; falls back to debug signing with a loud build-time warning when absent, rather than silently shipping a debug-signed "release." **A real keystore was not created or provided** — that's a deployment action for the team, not something to fabricate here. |
| ProGuard/R8 obfuscation + shrinking on release | IMPLEMENTED (this sprint), NOT VERIFIED by an actual build | Was previously not enabled at all for release. Now `isMinifyEnabled`/`isShrinkResources = true` with an explicit `proguard-rules.pro` keeping Flutter, Play Services Nearby, and this app's own `com.setu.*` packages (channel handlers referenced by string name, not by a reference R8 can trace). No Android SDK/Gradle available in this sandbox to actually run a release build and confirm nothing breaks at runtime — flagged, not claimed as tested. |

## Testing & scanning

| Control | Status | Notes |
|---|---|---|
| `flutter analyze` / `flutter test` | NOT AVAILABLE | No Dart/Flutter SDK in this sandbox (confirmed: dart-archive download returns HTTP 403 through the egress proxy) — this specific limitation is unchanged from earlier in the sprint |
| `pytest` (backend) | **RUN FOR REAL** (correction — see below) | `pip install -r requirements.txt` succeeded in this session (earlier "no Python environment" note was true for an earlier part of this sandbox session but not this one — corrected here rather than left standing). Full suite run against a local SQLite DB (never the real `.env` Postgres URL — that credential was never touched): **87 passed, 6 failed**. All 6 failures are **pre-existing**, confirmed by running the identical suite against commit `355e2ea` (before this security sprint) in a throwaway git worktree: `test_voice_status_reports_unavailable_without_whisper` + `test_voice_upload_returns_503_not_a_crash_when_unavailable` (openai-whisper/ffmpeg not installed in this sandbox, unrelated to this sprint), `test_all_new_routes_are_registered` (FastAPI/Starlette version mismatch: `route.path` isn't on `_IncludedRouter` in the installed version), `test_settings_have_sane_defaults` (asserts a hardcoded `postgresql://` prefix, fails under any non-Postgres `DATABASE_URL` including this run's SQLite override), and two pre-existing 422-vs-401 mismatches in `test_government_and_alerts.py` (`verify_responder_api_key`'s `Header(...)` returns 422 for a *missing* header by FastAPI's own default behavior, not the 401 those two tests assert — a pre-existing test/behavior mismatch, not something this sprint's changes caused). **Zero new failures from this sprint's changes.** |
| `Backend/tests/test_security_hardening.py` (this sprint's new tests) | **RUN FOR REAL, ALL PASS** | 35 tests: unit tests for `security.py`/`rate_limit.py`/`packet.py`/`user_profile.py`, plus two real end-to-end tests through `TestClient` confirming `POST /auth/request-otp` actually 429s after its configured limit and confirming the body-size guard actually returns 413 on a real request through the full ASGI stack (not just at the unit level) |
| Regression found + fixed by actually running the suite | Fixed | `InMemoryRateLimiter`'s module-level `_hits` state has no test-isolation reset, so an early OTP test's requests counted toward a later test's limit and caused 4 spurious 429 failures — same class of bug `conftest.py`'s pre-existing `_reset_duplicate_clusters` fixture solves for the AI dedup service. Fixed with a matching `_reset_rate_limiters` autouse fixture; re-run confirmed 0 regressions from this sprint after the fix. This is exactly why "test before/after a risky change" matters, and it would not have been caught by reading the code alone. |
| `pip-audit` / dependency vulnerability scan | NOT RUN | `pip` itself works in this sandbox (see above), but `pip-audit` was not installed/run this pass — a real, actionable follow-up now that installing packages here is confirmed possible (see §11 in the final report) |
| `npm audit` (dashboard) | NOT AVAILABLE | No Node/npm environment available in this sandbox session |
| Static analysis / SAST tool | NOT AVAILABLE | No SAST tool installed or run |
| Manual logic verification of pure-Dart algorithms (prior sprint's `PriorityRelayQueue`/`AdaptiveTtl`) | IMPLEMENTED (partial substitute) | Ported to Python, 27 assertions passed — explicitly documented as NOT equivalent to running the real Dart test suite (Dart/Flutter remains unavailable in this sandbox, unlike Python) |
| Penetration testing | NOT PERFORMED | No live target to test against in this sandbox; this document is a design/code review, explicitly not a pentest |

## Highest-priority follow-ups (not fixed this sprint, ranked)

1. **AI-driven dedup as an attack surface** (Threat Model T7) — a crafted
   message could cause a real new incident to be silently merged into an
   old one via the AI service's `is_duplicate` verdict. No safe fix
   attempted without a live AI service to test against.
2. **`POST /register` accepts any caller who knows a target's public
   `sender_id`** — no proof-of-possession, so citizen profile data
   (including medical history and emergency contacts) can be
   overwritten by anyone who has observed that device's public key.
   Needs a coordinated backend + `setu_app` `ProfileSyncService` fix
   (sign the registration payload, verify via the existing
   `signature_service.py`), not a backend-only change.
4. **A real release keystore has never been created for this app** —
   the signing mechanism is now wired up (see Mobile app table above),
   but the team must generate `android/key.properties` + a real
   `.keystore` before any build meant for distribution. Until that
   exists, `flutter build apk --release` still silently falls back to
   debug signing (now with a build-time warning, previously silent).
5. **Shared single API key with no per-responder identity/revocation** —
   architectural, needs a team decision.
6. **Dashboard's embedded API key is always extractable from the built
   bundle** — architectural limitation of a public SPA with a shared
   secret; a real fix needs per-user auth (e.g. the OTP flow extended
   into an actual session token), not a patch.
7. **No real (HTTP-header) CSP on the dashboard** — a meta-tag CSP was
   added this sprint; a header-based one needs a hosting-layer change
   this sprint had no visibility into.
8. **No dependency vulnerability scanning has ever been run** in this
   environment — should be run in CI or any environment with real
   network/package-manager access before a production launch.
