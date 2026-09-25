# SETU Block 3 — Security hardening & release security: validation report

Branch `feature/security-release-hardening` (from `feature/backend-contract-integrity` @ `0dec152`),
2026-09-24. Mesh, packet protocol, `MAX_TTL`, ACK and the packet `signaturePayload` were **not** changed.
No physical device was used. **Nothing here is an absolute claim that SETU is "secure"**; each line states
what was actually done and how it was checked.

Labels: **IMPLEMENTED** (code changed) · **VERIFIED** (executed here, evidence given) · **PARTIALLY VERIFIED** ·
**SOURCE REVIEW** · **BLOCKED** · **UNTESTED** · **KNOWN LIMITATION**.

## 1. Executive summary

| # | Issue from the brief | Status |
|---|---|---|
| 1 | Shared responder API key in the dashboard bundle | **IMPLEMENTED, VERIFIED** — no credential in the bundle; runtime login → short-lived signed bearer; build-time canary test proves an env-provided key never reaches the bundle |
| 2 | Registration proof-of-possession | **VERIFIED** enforced (Block 2 code, re-audited; 4 protected endpoints + route-policy gate) |
| 3 | Termination trust | **IMPLEMENTED, VERIFIED** — ADMIN-only provisioning, 64-hex key validation, revoke endpoint, empty registry fail-closed, persistence proven |
| 4 | Release APK debug-key fallback | **IMPLEMENTED, VERIFIED** — release build refuses without signing material; signed release APK inspected |
| 5 | Secret hygiene | **VERIFIED** clean (tracked files, full git history, dist, zips, node_modules); nothing to rotate *from this repo*; see §9 for what could not be checked |
| 6 | Android backup | **IMPLEMENTED, VERIFIED** in the built APK (`allowBackup=false` + extraction/backup rules) |
| 7 | Sensitive logging | **IMPLEMENTED** (Dart+Kotlin), guarded by `repo_guard` R7 (heuristic) |
| 8 | Dashboard security headers | **IMPLEMENTED, VERIFIED** — real response headers on the real build, and CSP exercised in real Chrome with zero violations |
| 9 | Dashboard mock/demo fallback | **IMPLEMENTED, VERIFIED** — off by default, compiled out of production bundles, explicit DEMO MODE otherwise |
| 10 | Dependency audit | **PARTIALLY VERIFIED** — pip-audit + npm audit clean; Dart/Gradle CVE audit **BLOCKED** (no tool) |
| 11 | CI security | **IMPLEMENTED**; **UNTESTED on a runner** |
| 12 | Cross-language verification in CI | **IMPLEMENTED**; gate script **VERIFIED locally**; CI job **UNTESTED on a runner** |
| 13 | Backend proxy configuration | **IMPLEMENTED** (explicit, warned at boot); real Render header chain **UNVERIFIED — deployment REQUIRED** |
| 14 | Production DB migration verification | **PARTIALLY VERIFIED** — verified on real PostgreSQL 18.4 scratch DB; **not** on the production DB |
| 15 | Real SMS/voice dependencies | **UNTESTED** (BLOCKED here: no gateway phone, no Whisper/ffmpeg) |

## 2. Threat surface (what an attacker can reach)
* Internet → FastAPI backend: `/ingest` (signed packets), device-signed endpoints, public read/OTP/login endpoints, admin/responder endpoints (credentialed) — see `ENDPOINT_POLICY.md`.
* Internet → dashboard static site (Vercel) → backend API with a bearer token.
* Radio → mesh (Nearby Connections): unchanged this block (Blocks 1–2).
* Device → local storage (Keystore-wrapped Ed25519 seed; PII in app-private SharedPreferences/SQLite), SMS radio.
* Supply chain: pub / Gradle / npm / pip dependencies, GitHub Actions.
* Build/release: signing key custody (not in this repo by design).

## 3. Authentication
* **Dashboard (IMPLEMENTED, VERIFIED):** `POST /auth/responder-login {key}` → constant-time compare → HMAC-SHA256 token (`v,role,iat,exp,jti`), default TTL 4 h, `SESSION_SECRET ≥ 32` chars else 503. Token in `sessionStorage` (tab-scoped). 401 anywhere ⇒ signed out. Login is rate-limited (10/5 min/IP) and failed attempts feed a 20/min brute-force damper (429). Tested: expired, tampered, wrong-secret, future-dated, wrong-version, role-escalation (`admin` claim, even correctly signed) tokens are refused.
* **Devices (VERIFIED):** Ed25519 request signatures with timestamp window and single-use nonce for `/register`, `/ingest/voice`, `/alerts/nearby`, `/alerts/{id}/respond`; cross-language byte-identical vectors (Dart↔Python).
* **KNOWN LIMITATION:** one shared responder key ⇒ no per-operator identity or individual revocation (only `jti` in audit text; rotation of `SESSION_SECRET` revokes all sessions). Per-user accounts would be a new auth system — deliberately not built. Tokens live in `sessionStorage`; an XSS would read them (mitigated by the strict CSP, §8).

## 4. Authorization
Access classes PUBLIC / INGEST / DEVICE / RESPONDER / ADMIN, enforced and gated by `test_endpoint_policy.py` (every route classified; anonymous → 401/403; ADMIN refuses responder key and session tokens). Provisioning/revoking trusted responder keys is ADMIN-only (`ADMIN_API_KEY`, distinct from the responder key; equal keys are flagged at boot); with no admin key configured the endpoints answer 503 instead of falling back. `/ingest` intentionally has no bearer requirement (offline delivery) but the packet signature is mandatory. **VERIFIED.**

**Termination end-to-end (VERIFIED by tests, SOURCE REVIEW for native):**
backend: unauthorized/unknown/citizen/forged-`responder_id` senders rejected, forged signature rejected first, empty registry rejected, revoked responder loses authority immediately, `emergency_id` matched by equality (`%`,`_`,`*` close nothing), registry persists across a new engine; mobile: `ResponderRegistry` empty ⇒ fail-closed, persisted across restart, exact (non-LIKE) queue cleanup (Block 1 tests in `block1_mesh_test.dart`, re-run in the matrix); native: `PacketRelayEngine`/`SignatureVerifier` (Block 1, unchanged). **UNTESTED on device.**

## 5. Cryptography
Ed25519 only (existing scheme). Request signatures use domain-separated canonical strings (`setu-req-v1|…`) that cannot parse as a packet payload. Session tokens: HMAC-SHA256, constant-time compare, secret ≥ 32 chars enforced. No new primitives; `signaturePayload` unchanged. The Dart→Python→Kotlin packet vector remains the interoperability proof (§12). **KNOWN LIMITATION:** R8 renames BouncyCastle Ed25519 classes in the release APK (present, mapped); release-mode signature verification on a device is **UNTESTED**.

## 6. Mobile security
* Private key: **VERIFIED** (tests + source scan) written only to `flutter_secure_storage` under one key, referenced only by `SigningService`, never in SharedPreferences, never logged/printed, no key/keystore asset bundled. **KNOWN LIMITATION:** profile, contacts, medical notes, child profiles, recovery log and location history are plaintext in app-private SharedPreferences/SQLite (protected by the Android sandbox only; backup now disabled).
* Backup: `allowBackup=false`, `fullBackupContent`, `dataExtractionRules` exclude every domain — **VERIFIED in the built APK** (aapt2). Product consequence, intentional: identity/queue do not migrate to a new phone (a restored copy would be a second holder of the same key).
* Cleartext/network: `usesCleartextTraffic=false` + `networkSecurityConfig` (system CAs only) — **VERIFIED in the APK**; no `http://` URL in app sources.
* Components (built APK, merged manifest): only `MainActivity` is exported among SETU's; `MeshForegroundService` not exported; `debuggable` absent (false). Library-added exported components: `…exposurenotification.WakeUpService` (guarded by GMS `EXPOSURE_CALLBACK` permission) and `androidx.profileinstaller.ProfileInstallReceiver` (guarded by `android.permission.DUMP`) — LOW, left as is (unused exposure-notification feature; removing library components was not risked without a device).
* Permissions reviewed (BLE/Wi-Fi Direct/location/SMS/mic/foreground service/internet) — all map to shipped features; `SEND_SMS` and `RECORD_AUDIO` are sensitive and runtime-gated. No change.
* Logging: phone numbers masked to 2 digits; response bodies and platform exception text no longer logged (they echo submitted values); Kotlin SMS handler likewise. Enforced by `tools/security/repo_guard.py` R7 — a **heuristic** (misses interpolation hidden inside function calls).

## 7. Backend security
CORS explicit (production origin only, no wildcard/credentials, localhost only in DEBUG); docs/OpenAPI off outside DEBUG; API security headers; body-size cap counts bytes (chunked verified); per-endpoint limits with explicit fail-open (SOS) / fail-closed; startup self-check warns for every missing production setting (values never logged). **Proxy configuration: `TRUSTED_PROXY_COUNT` is REQUIRED to be set explicitly to the *verified* number of proxies (0 if directly exposed). The Render/edge header chain could not be verified here, so no value is asserted.** The code default remains 1 (documented assumption) and the boot log warns when it is not set. Multiple workers ⇒ per-process limits (Procfile runs one uvicorn worker). **VERIFIED** (tests) / **UNVERIFIED** (deployment).

## 8. Dashboard security
* No secret in JS: **VERIFIED** by a build test that injects a canary into `VITE_*` variables and proves it (and any `X-API-Key` string) is absent from the bundle. (This test caught a real leak vector: reading the whole `import.meta.env` inlines *every* `VITE_*` variable; the source now uses three individual compile-time defines.)
* Headers: CSP (`script-src 'self'`, no `unsafe-eval`, no inline scripts, `style-src` without inline elements, `frame-ancestors 'none'`, https-only `connect-src`, `object-src 'none'`, `upgrade-insecure-requests`), HSTS, `X-Frame-Options: DENY`, `nosniff`, `Referrer-Policy: no-referrer`, `Permissions-Policy`, COOP/CORP — defined once in `vercel.json`, applied to `vite preview`, **VERIFIED on the real build over HTTP** (`tests/headers.test.mjs`); **VERIFIED in real Chrome** (`npm run check:csp`: login rendered, dashboard rendered after sign-in against a mock backend, 0 CSP violations, negative control detected). The meta-tag CSP was removed. `vercel.json` itself is **UNTESTED on Vercel** (platform behaviour not exercised); `connect-src` names `https://setu-backend-cy78.onrender.com` and must match `VITE_BACKEND_URL`. **KNOWN LIMITATION:** Google Fonts stylesheet/fonts and map-marker images (`raw.githubusercontent.com`, `unpkg.com`) are third-party origins allowed by CSP (no SRI); `style-src-attr 'unsafe-inline'` is needed for inline style *attributes* (React/Leaflet/Recharts).
* Mock/demo: default off; `VITE_DEMO_MODE=true` builds an explicit demo (banner, no backend). Production bundle contains none of the sample datasets (marker test). API failures surface as errors (banner, drawer alert, teams error state); `resolve` marks an incident closed only after backend confirmation; `New Alert` (which fabricated a local incident) is demo-only; a production build without an `https://` `VITE_BACKEND_URL` reports a configuration error instead of silently calling localhost.

## 9. Secret hygiene (Phase 16)
Checked, without printing values: `git ls-files` (only `*.example` env/properties files), **full git history** (no `.env`/keystore/key/PEM ever committed), pattern scan of tracked text files (AWS/Google/GitHub/Slack/OpenAI-style keys, private-key blocks, JWTs, assigned secrets — 0 findings), dashboard `dist` (current and the old zip's bundle: no key material), both untracked archive ZIPs, local `.env` files (only variable *names/emptiness* inspected: `Backend/.env` has no filled secret; the stale root `setu_ai_service/.env` holds a 13-character `GEMINI_API_KEY` that is not Google-key-shaped — a placeholder, SOURCE REVIEW). No real secret was found in this repository, so nothing was rotated from here. **BLOCKED / REQUIRED (cannot be done from this environment):** if the deployed dashboard on Vercel was ever built with `VITE_API_KEY` set, that key was public — **rotate `RESPONDER_API_KEY` on Render and remove the Vercel variable**; also review Render/Vercel/Neon environment variables and the SMS gateway/SMTP credentials there. `tools/security/repo_guard.py` (+ CI job) keeps these classes of leak out from now on; `*.zip` and the retired `setu_ai_service/` are ignored. Deleting a local file is not rotation and none was claimed.

## 10. Database (Phase 15)
See `POSTGRES_MIGRATION_RUNBOOK.md`. **VERIFIED on real PostgreSQL 18.4 (scratch DB):** legacy→new identity migration preserves every row, is idempotent, transactional (failed upgrade keeps the old unique index), documented rollback behaves as stated, ingest pipeline incl. `pg_advisory_xact_lock`/dedup works, 8 concurrent identical uploads ⇒ one ACCEPT and no 5xx. **UNTESTED** against the production database/version.

## 11. Dependencies (Phase 17)
| Ecosystem | Tool | Result | Classification / action |
|---|---|---|---|
| Python (pinned) | `pip-audit` | **no known vulnerabilities** | — |
| Python (unpinned: `sentence-transformers`, `numpy`, `openai-whisper`, `email-validator`, `python-multipart`) | — | not auditable as unpinned | **KNOWN LIMITATION** — pin when the deploy image is fixed |
| npm | `npm audit` | initially 2 high (`nanoid` via vite/postcss — reachable from a prod dependency; `js-yaml` via eslint — dev) | **fixed** with `npm audit fix` (lockfile only); now **0 vulnerabilities**; tests/build/Chrome check re-run |
| Dart/Flutter | `dart pub audit` does not exist in this SDK; `flutter pub outdated` only | **BLOCKED** (no advisory source) | direct deps behind latest major: `connectivity_plus`, `flutter_secure_storage`, `go_router`, `permission_handler` — **not upgraded** (major bumps could break the mesh/permission flows; needs device testing) |
| Gradle/Android | no OSV/dependency-check tool | **BLOCKED** | native crypto dep `org.bouncycastle:bcprov-jdk18on:1.78.1` noted; verify against advisories in a networked review |
Dependabot config added for all five ecosystems + Actions.

## 12. CI (Phase 18/19)
`.github/workflows/setu-ci.yml` rewritten: `permissions: contents: read`, no secrets used or printed, checkout without persisted credentials, **every action pinned to a full commit SHA** (SHAs read from the upstream repos; tags in comments), concurrency + timeouts; jobs: repo security guard, Flutter analyze/test, backend pytest + AI tests + pip-audit + dashboard tests/build/`npm audit --omit=dev --audit-level=high`, cross-language gate, native unit tests, debug APK + **assertion that a release build without signing material is refused**. `tools/cross_lang/run_gate.sh`: Dart signs → Python verifies → Kotlin verifies; requires the full vector set (genuine + tamper of message, timestamp, latitude, longitude, sender_id, signature, nonce, packet_id, emergency_id, priority + the relay-rewrite case that must still verify), fails if the Kotlin test is *skipped*; `signaturePayload` untouched. **No workflow has run on a GitHub runner from this environment — CI is IMPLEMENTED, not VERIFIED.**

## 13. Release signing (Phase 7)
`android/app/build.gradle.kts`: signing material from `android/key.properties` (gitignored) or `SETU_RELEASE_*` env vars; any signed-release task (`assembleRelease|packageRelease|bundleRelease|…`) **fails with "SETU RELEASE BUILD REFUSED"** when it is missing/incomplete/points to a missing file; `signingConfig` is `null` unless configured — there is no reference to the debug config (guard rule R5, Dart test, CI assertion).
* Evidence, no signing material: `flutter build apk --release` → `BUILD FAILED … SETU RELEASE BUILD REFUSED: Release signing is not configured …` (VERIFIED).
* Evidence, with a **throwaway** keystore generated for the test only (not committed, not production): release APK built; `apksigner verify --print-certs` → *Verifies*, 1 signer, `CN=SETU THROWAWAY VERIFICATION KEY, O=not-for-distribution` (not the Android debug certificate; this machine has no `~/.android/debug.keystore` to compare digests with) (VERIFIED). Only APK Signature Scheme v2 is present (v1/v3 absent; fine for minSdk ≥ 24).
* **BLOCKED / REQUIRED:** the production keystore must be generated and kept by the release owner (`keytool` command in `key.properties.example`); a build signed with the throwaway key must not be distributed.

## 15. Known limitations (not fixed; nothing hidden)
1. One shared responder credential; no per-operator identity, no per-session server-side revocation (rotate `SESSION_SECRET`). **KNOWN LIMITATION**
2. Dashboard token in `sessionStorage`; XSS would expose it (CSP is the mitigation). **KNOWN LIMITATION**
3. Third-party origins in the dashboard CSP (Google Fonts, marker images from GitHub/unpkg) without SRI. **KNOWN LIMITATION**
4. Device identities are self-issued keys: nothing stops an attacker from minting keys beyond the rate limits (Block 2 limitation, unchanged). **KNOWN LIMITATION**
5. Rate limiting is per process and in memory; distributed abuse needs an edge/WAF layer. **KNOWN LIMITATION**
6. PII (profile, contacts, medical notes, child profiles, recovery/location history) is stored unencrypted in app-private storage. **KNOWN LIMITATION**
7. Repo guard R7 (sensitive logs) is a heuristic; `flutter analyze` has 13 pre-existing style infos (CI uses `--no-fatal-infos`). **KNOWN LIMITATION**
8. Dart and Gradle dependency CVE audits could not be run (no advisory tool). **BLOCKED**
9. ACK is still exit-node-signed, not backend-attested (Block 1/2 limitation, unchanged). **KNOWN LIMITATION**
10. Release-mode (R8) native signature verification and everything radio/SMS/voice/foreground-service related: **UNTESTED on a device**.
11. `flutter build apk --release` cold builds take several minutes here; the signing guard triggers only after Gradle configuration (correct, but not instant).

## 16. Deployment blockers (must be done by whoever operates the deployment)
1. **Rotate `RESPONDER_API_KEY`** on Render and delete any `VITE_API_KEY` from Vercel/CI (a Vite variable is public); redeploy the dashboard from this branch.
2. Set on Render: `RESPONDER_API_KEY` (≥ 32 random chars), **`ADMIN_API_KEY`** (different), **`SESSION_SECRET`** (≥ 32), `DEBUG=false`, `CORS_ALLOWED_ORIGINS_RAW=<exact dashboard origin>`, and **`TRUSTED_PROXY_COUNT=<verified value>`** (verify the real `X-Forwarded-For` chain first; do not guess). Read the boot log for `CONFIG:` warnings — there must be none.
3. Confirm `vercel.json` is picked up (`curl -I` the deployed dashboard and compare with `tests/headers.test.mjs`) and that its `connect-src` origin equals the deployed backend.
4. Generate and safeguard the **production Android keystore**; build the release with `key.properties` or `SETU_RELEASE_*` secrets; never distribute the throwaway-key APK.
5. Run the PostgreSQL migration procedure on a copy, then production (`POSTGRES_MIGRATION_RUNBOOK.md`); deploy backend before shipping the app (signed-request endpoints).
6. Provision trusted responder keys through `POST /responders` with the admin key; verify `GET /responders/keys`.
7. Install real dependencies (`openai-whisper` + ffmpeg, `sentence-transformers`) and configure the SMS gateway/SMTP **only via environment**; re-verify voice and SMS end to end (UNTESTED here).
8. Run CI once on GitHub and fix whatever a real runner surfaces.

## 17. Device-test prerequisites
* Two or more Android phones (≥ 8 recommended for relay chains), Android 12+ (BLE/Nearby permissions), SIMs for SMS tests, one phone with data and one without.
* A **release-mode** build signed with a non-production test keystore (to exercise R8 + BouncyCastle Ed25519 verification and the manifest as shipped), plus a debug build.
* Backend deployed (or reachable staging) with the production-shaped configuration in §16 and a test responder key provisioned; dashboard on the real origin.
* Cases to run: cross-device signature interoperability, unauthorized/authorized termination and queue cleanup, registration → nearby alerts → respond, voice SOS, SMS single-send vs backend, airplane-mode relay → exit-node upload → ACK, Android backup/restore refusal (`adb shell bmgr`), reinstall behaviour of the Keystore-wrapped identity, log review (`adb logcat`) for phone numbers/bodies/keys.

## 14. Test results (exact, this environment; Python 3.14.4, Flutter 3.44.8, Node 24, JBR 17, PostgreSQL 18.4 embedded)
| Command | Result |
|---|---|
| `cd Backend && pytest -q` | **399 passed, 6 skipped** (the 6 are the PostgreSQL tests, skipped without `SETU_TEST_POSTGRES_URL`) |
| same with `SETU_TEST_POSTGRES_URL=<scratch PG 18.4>` `pytest tests/test_postgres_integration.py` | **6 passed** |
| `cd Backend/setu_ai_service && pytest -q` | 38 passed (Block 2 run; not re-run this block, unchanged) |
| `cd setu_dashboard && npm test` | **20 passed** (contract, secret canary, demo elimination, session/API failure, headers on real build) |
| `npm run build`; `npm run check:csp` (headless Chrome) | built; login + dashboard rendered, **0 CSP violations**, negative control detected |
| `npm audit` | **0 vulnerabilities** (after `npm audit fix`) |
| `pip-audit` (pinned reqs) | no known vulnerabilities |
| `python tools/security/repo_guard.py` | 0 findings |
| `flutter analyze` | 13 `info`, **0 warnings/errors** (exit 1 only because infos are fatal by default; CI uses `--no-fatal-infos`) |
| `flutter test` | **197 passed** (includes new `mobile_security_test.dart`) |
| `./gradlew :app:testDebugUnitTest` | BUILD SUCCESSFUL |
| `./gradlew :app:assembleDebug` | BUILD SUCCESSFUL |
| `tools/cross_lang/run_gate.sh` | **PASS**: Python `RESULT: PASS`; Kotlin `tests=1 skipped=0 failures=0` (first run exposed a wrong report path in the gate script — fixed; a plain unit-test run overwrites the report with `skipped=1`, which the gate correctly treats as failure) |
| `flutter build apk --release` (no signing material) | **refused**, `SETU RELEASE BUILD REFUSED` (exit 1) |
| `flutter build apk --release` (throwaway keystore) | Built `app-release.apk` 58.2 MB; `apksigner`: verifies, 1 signer, throwaway CN |
Failure classification: no test failures. Pre-existing/other: dashboard `eslint` config crash (unchanged, PRE-EXISTING); the shared checkout was, during this block, switched to another branch with uncommitted, non-compiling UI edits by another session — all Block 3 work was therefore built and tested from a separate git worktree (`/home/vaibhav/SETU_FINAL_block3`), which is ENVIRONMENT, not a SETU defect.
