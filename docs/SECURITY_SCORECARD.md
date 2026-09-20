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
| Content-Security-Policy header | NOT IMPLEMENTED | No CSP present (`index.html` has no CSP meta tag; would need to be set at the hosting/CDN layer for a static Vite build) — flagged as a follow-up, not fixed this sprint (out of scope: no visibility into the actual deployment's hosting config) |
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
| `flutter analyze` / `flutter test` | NOT AVAILABLE | No Dart/Flutter SDK in this sandbox (confirmed: dart-archive download returns HTTP 403 through the egress proxy) |
| `pytest` (backend) | NOT AVAILABLE | `fastapi`/`pydantic`/etc. not installed, no way to install them here |
| `pip-audit` / dependency vulnerability scan | NOT AVAILABLE | Same — no Python environment |
| `npm audit` (dashboard) | NOT AVAILABLE | No `node_modules` installed, no network path to run `npm install` verified in this sandbox |
| Static analysis / SAST tool | NOT AVAILABLE | No SAST tool installed or run |
| Manual logic verification of pure-Dart algorithms (prior sprint's `PriorityRelayQueue`/`AdaptiveTtl`) | IMPLEMENTED (partial substitute) | Ported to Python, 27 assertions passed — explicitly documented as NOT equivalent to running the real Dart test suite |
| This sprint's new Python code (`rate_limit.py`, `security.py`, `packet.py` validators) | NOT VERIFIED by execution | No Python environment available to import/run it; correctness was reasoned through by careful reading and manual trace, not proven by a passing test run |
| Penetration testing | NOT PERFORMED | No live target to test against in this sandbox; this document is a design/code review, explicitly not a pentest |

## Highest-priority follow-ups (not fixed this sprint, ranked)

1. **AI-driven dedup as an attack surface** (Threat Model T7) — a crafted
   message could cause a real new incident to be silently merged into an
   old one via the AI service's `is_duplicate` verdict. No safe fix
   attempted without a live AI service to test against.
2. **A real release keystore has never been created for this app** —
   the signing mechanism is now wired up (see Mobile app table above),
   but the team must generate `android/key.properties` + a real
   `.keystore` before any build meant for distribution. Until that
   exists, `flutter build apk --release` still silently falls back to
   debug signing (now with a build-time warning, previously silent).
3. **Shared single API key with no per-responder identity/revocation** —
   architectural, needs a team decision.
4. **Dashboard's embedded API key is always extractable from the built
   bundle** — architectural limitation of a public SPA with a shared
   secret; a real fix needs per-user auth (e.g. the OTP flow extended
   into an actual session token), not a patch.
5. **No CSP on the dashboard** — needs a hosting-layer change this
   sprint had no visibility into.
6. **No dependency vulnerability scanning has ever been run** in this
   environment — should be run in CI or any environment with real
   network/package-manager access before a production launch.
