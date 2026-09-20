# SETU Security + Production Hardening Sprint — Final Report

Sep 2026. Continuation of the mesh-engineering sprint (mesh_service.dart
etc., commits `feffc33`/`ea58dc1`/`355e2ea`, verified intact and
unmodified before this sprint began). This report covers the security
audit + hardening pass only.

## 1. Scope and method

Inspected the real repository (Flutter/Kotlin mesh app, FastAPI backend,
React dashboard, vendored `setu_ai_service`) by reading source directly —
no assumptions from filenames, comments, or prior summaries taken at face
value (several stale comments elsewhere in the codebase were found to
describe things no longer true, e.g. signature verification once
mislabeled a "stub"). No live target existed to test against, so this is
a **design and source-code security review**, not a penetration test —
stated explicitly per the sprint brief's own requirement never to claim
pentesting occurred.

## 2. Threat model summary

Seven threat actors (T1 malicious mesh peer, T2 passive eavesdropper, T3
malicious internet client, T4 compromised/rogue responder, T5
compromised dashboard client, T6 supply-chain, T7 malicious AI input),
full detail in `docs/SECURITY_THREAT_MODEL.md`. The most consequential
new finding: **T7 — the AI-driven duplicate-detection path
(`ai_analysis_service.py`) is now the dedup source of truth** per a
reversed team decision documented in that file's own comments, meaning a
crafted emergency message could in principle cause a genuine new
incident to be silently merged into an old one. Not fixed this sprint
(no live AI service to safely test a change against) — flagged as the
top follow-up.

## 3. Vulnerabilities found and fixed

| # | Finding | Severity | Fix |
|---|---|---|---|
| 1 | Responder API-key comparison used `!=` (timing side-channel) | Low | `hmac.compare_digest` |
| 2 | `RESPONDER_API_KEY` silently defaults to `"changeme-dev-key"` with no production check | Medium | Fail-fast 500 on boot when `debug=False` and the key is still the default |
| 3 | `/ingest`'s `PacketIn` fields (message, coordinates, hop_count, relay_path, etc.) were effectively unbounded | Medium | Explicit `Field(..., max_length=…, ge=…, le=…)` on every field, plus a `field_validator` bounding each `relay_path` entry |
| 4 | `PacketBatchIn.packets` had no upper bound | Medium | Capped at 500 |
| 5 | No rate limiting anywhere in the API | Medium | New tiered in-memory limiter: AUTH (10/5min), RESPONDER ACTION (20/min), PUBLIC WRITE (30/min) on the six routes that need it; `/ingest` and other emergency-critical routes deliberately left uncapped |
| 6 | No global request body-size guard | Low | New Content-Length-based middleware, 413 above 30MB |
| 7 | **Android release builds were signed with the shared Flutter debug keystore** (`build.gradle.kts` unconditionally used `signingConfigs.getByName("debug")` for `release`) | **High** (a debug-signed release is not a real, verifiable publisher signature and would be rejected by Google Play outright) | Wired `signingConfigs.release` from a gitignored `android/key.properties` when present, with a loud build-time warning and safe debug fallback when it's absent — no real keystore fabricated, see §4 |
| 8 | R8/ProGuard shrinking + obfuscation was not enabled for Android release builds | Low-Medium | `isMinifyEnabled`/`isShrinkResources = true` plus an explicit `proguard-rules.pro` keeping Flutter + Play Services Nearby + this app's own `com.setu.*` channel-handler packages |
| 9 | No Content-Security-Policy anywhere in the dashboard | Low-Medium | Added a scoped `<meta http-equiv="Content-Security-Policy">` to `index.html` (real HTTP-header CSP still needs a hosting-layer change, see §4) |

## 4. Vulnerabilities found and NOT fixed (with reasons)

| # | Finding | Severity | Why not fixed |
|---|---|---|---|
| 1 | AI-driven dedup can be influenced by crafted message text (T7) | High (availability/integrity) | No live AI service to test a fix against; vendored third-party-owned code |
| 2 | Single shared API key for all responders, no per-responder revocation | Medium-High | Architectural change, needs a team decision, not a hardening patch |
| 3 | Dashboard's `X-API-Key` is always extractable from the built JS bundle | Medium | Inherent to a public SPA + shared-secret model; a real fix is per-user session auth, out of scope |
| 4 | CORS `allow_methods`/`allow_headers` are `*` | Low | Can't verify a narrower list against the live dashboard in this sandbox without risking breakage |
| 5 | No real release keystore has ever been generated for the Android app | High (blocks any real release, not just a security nicety) | Signing is now wired (see §3, finding 7) but a real `.keystore`/`key.properties` must be created and kept by the team — never something to fabricate in an automated pass |
| 6 | Real HTTP-header CSP for the dashboard (vs. the meta-tag version added this sprint) | Low | Needs a hosting/CDN-layer change outside this sprint's visibility |
| 7 | No dependency vulnerability scanning ever run | Unknown | No network/package-manager access in this sandbox — see §7 |

## 5. Confirmed clean (verified, not assumed)

- No hardcoded secrets in source (grepped for key/token/password/secret literal patterns across Backend/setu_app/setu_dashboard/setu_ai_service — no matches outside `.env`/test/example files).
- `.env` files with real populated values exist on disk (`Backend/.env`: FOUND, non-empty; `setu_ai_service/.env`: FOUND, non-empty) but are correctly `.gitignore`d and **not tracked** — verified via `git ls-files`, zero `.env` files tracked.
- No SQL injection surface: SQLAlchemy ORM throughout; the one raw-SQL call (`pg_advisory_xact_lock`) is parameterized.
- No command injection surface: zero `subprocess`/`os.system`/`shell=True`/`eval`/`exec` anywhere in `Backend/app`.
- No SSRF surface: the only outbound HTTP call (`sms_service.py`) targets a hardcoded constant URL, never attacker-controlled input.
- No secret values logged anywhere (grepped every logger/print call for password/secret/key/token/signature).
- No `dangerouslySetInnerHTML` in the dashboard.
- AndroidManifest exports only the required launcher activity; the mesh foreground service is `exported=false`; no cleartext traffic config; all app-side backend URLs are `https://`.
- No stack traces or internal exception text returned to API callers (spot-checked routers all raise `HTTPException` with fixed `detail` strings).

## 6. New documentation produced

- `docs/SECURITY_THREAT_MODEL.md`
- `docs/API_SECURITY_MATRIX.md`
- `docs/SECURITY_ARCHITECTURE.md`
- `docs/SECURITY_SCORECARD.md`
- `Backend/tests/test_security_hardening.py`

## 7. What could not be run (NOT AVAILABLE, stated honestly)

- `flutter analyze` / `flutter test` — no Dart/Flutter SDK in this sandbox (dart-archive download returns HTTP 403 through the egress proxy).
- `pytest` — `fastapi`/`pydantic`/etc. not installed, no way to install them here.
- `pip-audit`, `npm audit`, any SAST tool — same environment limitation.
- Any live penetration test — no reachable deployed target.

None of these were simulated or faked. `docs/SECURITY_SCORECARD.md` marks each as **NOT AVAILABLE**, distinct from **NOT IMPLEMENTED**.

## 8. Wire protocol / architecture preserved as instructed

- Mesh signature payload deliberately excludes `ttl`/`hop_count` — confirmed intentional (they mutate per relay hop) by reading `signature_service.py` directly; left unchanged.
- Nearby Connections / PacketRelayEngine / dedup cache / MeshServiceImpl — not touched this sprint (all security changes are backend-only).
- `/ingest` and `/ingest/batch` remain unauthenticated by design (signature-verified instead) and deliberately unrate-limited.
- No new authentication was added to `/ingest` that would break offline Exit Node ingestion.
- No blind package upgrades — `requirements.txt`/`package.json` versions untouched.

## 9. Rate limiting design rationale

Explicitly NOT one global arbitrary limit. Three tiers matched to actual risk and actual legitimate usage patterns (auth brute-force, privileged responder writes, public citizen writes), with the emergency-critical `/ingest` path left uncapped on purpose — detailed reasoning in `Backend/app/core/rate_limit.py`'s own module docstring and in the threat model's T3 section.

## 10. Git state

`42a6647` (backend hardening) → `24c831b` (this doc) → `02e7e57` (Recovery module, Priority 8 — the last fully-unstarted item from the prior mesh-engineering sprint, closed out during this session) → `b349f27` (Android release-signing + R8) → `dc5573c` (dashboard CSP), all on top of the prior sprint's `355e2ea`. Working tree clean after each commit; `.env` files and other untracked local files were reviewed and correctly excluded, never staged.

## 11. Recommended next steps, ranked

1. Design a safe test/mitigation for AI-dedup manipulation (T7) — ideally with a real (even sandboxed) Gemini call available to verify against.
2. Generate a real Android release keystore and `android/key.properties` (see `android/key.properties.example`) — signing is wired but unusable for a real release without it.
3. Move from a single shared responder API key to per-responder credentials with real revocation and an audit trail of who accessed what.
4. Add a real HTTP-header CSP at the hosting layer for the dashboard (the meta-tag version added this sprint is real but weaker defense-in-depth).
5. Run `pip-audit`/`npm audit`/`flutter pub outdated` in any environment with real network/package-manager access, and review results before a production launch — also run an actual `flutter build apk --release` once possible, to confirm the new ProGuard rules don't break the mesh layer at runtime.
6. Revisit CORS `allow_methods`/`allow_headers` narrowing once the live dashboard's actual method/header usage can be observed and tested against.

## 12. Explicit statement on claims

No penetration testing was performed. No dependency scan was run. No
Flutter or backend automated test suite was executed in this sandbox —
new tests were written but not run. Every "IMPLEMENTED" status in
`docs/SECURITY_SCORECARD.md` reflects either a pre-existing control
verified by direct code reading, or a new control added and reasoned
through manually; none reflect a passing automated test run in this
environment. All limitations are stated above and in the scorecard,
not omitted.
