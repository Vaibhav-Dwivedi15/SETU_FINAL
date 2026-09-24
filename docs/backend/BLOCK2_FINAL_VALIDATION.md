# SETU Block 2 — Backend + Contract Integrity: Final Validation

Branch `feature/backend-contract-integrity` (from `feature/mesh-stability-final` @ `7e9bd17`),
2026-09-24. Mesh architecture, Nearby Connections, `P2P_CLUSTER`, `MAX_TTL` (5) and the
packet `signaturePayload` were **not** touched. No device was used; nothing below is
device-verified.

Labels: **IMPLEMENTED** (code written) · **VERIFIED** (executed here, result shown) ·
**PARTIALLY VERIFIED** · **SOURCE REVIEW** · **BLOCKED** · **UNTESTED** · **KNOWN LIMITATION**.

## 1. Baseline
`docs/backend/BLOCK2_BASELINE.md`. Before any change (VERIFIED): with the environment fixed,
`pytest` = 89 passed / 4 failed of 93; every module errored at import because the
developer-local `Backend/.env` has an empty `DATABASE_URL` (ENVIRONMENT). The 4 failures:
1 ENVIRONMENT (test read the exported `DATABASE_URL`), 1 DEPENDENCY/TEST BUG (FastAPI 0.141
`app.routes` contains path-less `_IncludedRouter`), 2 PRE-EXISTING real bug (missing
`X-API-Key` ⇒ 422 instead of 401). All fixed and classified in commit `a64d032`.

## 2. Contract changes (every consumer updated in the same branch)
| Change | Backend | Mobile | Dashboard |
|---|---|---|---|
| `/ingest` per-packet states | `accepted/duplicates/rejected/failed` + `status`,`code` | `classifyIngestResponse` + `IngestResult` (legacy shape still understood) | — |
| packet identity `(sender_id, packet_id)` | model + idempotent DB upgrade | — | — |
| signed requests (`X-Setu-*`) | `request_auth.py`; register/voice/nearby/respond | `RequestSigner` + 4 services | — |
| `IncidentOut` fields | +sender_priority, ai_*, relay_path, display_priority, report_count, updated_at; audit `id` | — | `normalizeIncident` uses them |
| `sms_contacts_notified` | ingest accepted/duplicate entries, voice | `SosRepository` skips direct SMS iff covered | — |
| `TRUSTED_PROXY_COUNT` | new setting (default 1) | — | — |

**Deployment ordering (important):** `/register`, `/ingest/voice`, `/alerts/nearby`,
`/alerts/{id}/respond` now *refuse unsigned requests*. An installed pre-Block-2 app will get
401 on those (profile sync fails, nearby list is empty, voice SOS fails) until it is
updated; `/ingest` and `/responders/keys` remain compatible with old apps except that an old
app reads a duplicate as `failed` and retries it (harmless, never a false delivery).
Ship backend and app together.

## 3. Security changes (all IMPLEMENTED; behaviour VERIFIED by tests in §14)
* Authentication precedes dedup; forged / stale / unsigned packets can never occupy a `packet_id`.
* Proof of possession for registration (no more overwrite of a victim's profile from a public key).
* Voice ingest authenticated by device key; `emergency_id` must belong to the caller; bounded
  read, magic-byte sniff, content-type/filename/coordinate/priority validation, controlled 4xx.
* Nearby alerts / respond require a signed, **registered** key; minimal data; bounded; rate limited.
* Body cap counts bytes (chunked/lying `Content-Length` no longer bypass it), per-path caps.
* Client-IP no longer trusts a client-supplied `X-Forwarded-For`; limiters bounded, fail-open only
  where an SOS is at stake; failed API-key attempts are damped.
* AI dedup proposals verified by the backend; closed incidents cannot absorb new emergencies.
* SMS idempotency ledger; numbers masked, bodies never logged.
* Last-resort handler: no traceback/SQL/path ever reaches a client.

## 4. Ingest semantics — IMPLEMENTED, VERIFIED
`ACCEPTED / DUPLICATE / REJECTED / FAILED`, HTTP 200 for a processed batch; every packet
reported exactly once with `packet_id`. Tested: accepted, duplicate, invalid signature, stale,
future-dated, invalid TTL (0, 9, −1), malformed (non-object, missing fields, bad values, NaN/∞),
oversized (8000-byte UTF-8 message), unknown/`ack`/`alert` types, unauthorized termination
(then accepted after registration), 500-packet cap, DB failure ⇒ `FAILED retryable` leaving no
state that would turn the retry into a "duplicate". Squatting (6 required cases + legacy junk
row + shared `emergency_id`): `TestPacketIdSquatting`.

## 5. ACK semantics — IMPLEMENTED (unchanged protocol), VERIFIED (mesh harness)
ACK ⇔ backend held the packet (`ACCEPTED` or `DUPLICATE`); never after `REJECTED`, `FAILED`,
429/5xx or network failure (new/existing `block1_mesh_test.dart` cases: accepted→ACK,
duplicate→one ACK, rejected→none, failed→none and stays queued). No ACK/alert upload loop is
possible (§ PACKET_CONTRACT.md 1). **KNOWN LIMITATION:** the ACK is still generated and signed
by the exit node, not by the backend.

## 6. Registration — IMPLEMENTED, PARTIALLY VERIFIED
Python: valid, invalid signature, wrong key, key/identity mismatch, replay of a captured request,
expired/future timestamp, tampered body, cross-path reuse, packet-signature-as-request-signature,
malformed headers/payloads, no-overwrite of an existing profile. Dart: signature/canonical string
byte-identical to Python from a shared vector file. **UNTESTED:** the real `registerProfile` HTTP
call on a device, and real clock skew (window ±300 s).

## 7. Voice — IMPLEMENTED, PARTIALLY VERIFIED
Backend tests stub `transcribe`/`transcription_available` (Whisper + ffmpeg are not installed
here). **UNTESTED:** real transcription, multipart assembly by the Dart client (only its
canonical/signature is vector-tested), 25 MB uploads end to end. **KNOWN LIMITATION:** any fresh
keypair can file a voice report (SETU has no identity issuance); per-IP/per-key limits are the
control.

## 8. Rate limits — IMPLEMENTED, VERIFIED (in-process)
`/ingest` 300 req + 3000 packets / min / IP (fail open); `/register` 10/min/IP + 10/10 min/key;
`/ingest/voice` 10/min/IP + 5/5 min/key; `/alerts/nearby` 60/min/IP + 30/min/key; `/respond`
30/min; `/responders/keys` 60/min (fail open); OTP 10/5 min; API-key failures 20/min.
Verified: 429 + `Retry-After`, packet budget counts packets, no data loss on 429, 60 sequential
SOS uploads unthrottled, rotating spoofed `X-Forwarded-For` cannot bypass, fail-open vs
fail-closed, bounded memory. **KNOWN LIMITATION:** per process (N workers ⇒ N× limit); no
distributed store. **UNTESTED:** that `TRUSTED_PROXY_COUNT=1` matches Render's real header chain
— verify on the deployment (0 if reachable directly).

## 9. Dashboard contract — IMPLEMENTED, VERIFIED
Golden example `Backend/tests/contract/incident_out.example.json`; pytest proves the live API
matches it, `npm test` (node) proves `normalizeIncident` consumes it; `npm run build` OK.
Found + fixed while doing this: `resolve_incident_by_id` had no `return`, so the first
"Mark Resolved" closed the incident but answered **404** (PRE-EXISTING, fixed, regression-tested).
`relay_id` (named in the brief) does not exist in dashboard or backend; nothing added.
**UNTESTED:** visual rendering of the critical modal / drawer (no browser used).

## 10. AI dedup — IMPLEMENTED, VERIFIED (lexical path)
Every accepted emergency returns `dedup_decision`, `matched_incident_id`, `dedup_reason`,
`dedup_evidence`; the AI service also returns `dedup_reason`. Scenarios tested: same incident,
nearby duplicate, different incident nearby, same text/different location, same
location/different disaster, different category (forced AI proposal → veto), backend distance
veto, unresolved cluster, closed incident + new emergency (mutation-checked: disabling the veto
fails the test), third report joins the new open incident, no-GPS merge flagged
`location_verified:false`, AI-unavailable fallback. **UNTESTED:** embedding path
(`sentence-transformers` not installed). **KNOWN LIMITATIONS:** AI cluster state is in-memory,
per-process, resets on restart, keyed on server receipt time; after a veto the AI does not
learn the new incident's cluster (backend fallback covers OPEN incidents within 150 m/15 min).

## 11. SMS — IMPLEMENTED, VERIFIED (gateway stubbed)
Authoritative sender: the backend gateway once it has accepted the packet, exactly once per
new incident, to the sender's registered contacts (`UNIQUE(event, contact_hash)` ledger; retry
or duplicate upload re-attempts only *failed* contacts; merges never send; duplicate numbers
send once; ledger stores hashes only; logs mask numbers and omit bodies). The mobile app sends
its direct SMS only when the backend did not confirm SMS for all distinct device contacts
(offline / unreachable / unregistered). **KNOWN LIMITATIONS:** gateway "queued" ≠ delivered
(the demo gateway is one Android phone that must be online — if it is offline the contact gets
nothing and the app has already skipped its own SMS); contacts count as "covered" only by count
(a stale backend contact list ⇒ possible duplicate, never silence). **UNTESTED:** real gateway,
real device SMS, `SosRepository` skip logic (compiled/analyzed, not unit-tested).

## 12. Nearby alerts — IMPLEMENTED, VERIFIED
Anonymous 401; unregistered 403; registered OK; ≤20 rows; distance at 100 m; no coordinates,
identity, profile or contacts; replay/tamper/relocation of a captured request refused; closed
incidents hidden. **KNOWN LIMITATION:** "registered" means "self-registered a key with PoP" —
a determined attacker can mint keys; per-IP/key limits and 100 m/20-row bounds limit
enumeration but do not eliminate it. Users with no synced profile see an empty list (403).

## 13. AI canonicalization — IMPLEMENTED, VERIFIED
`Backend/setu_ai_service/` is canonical (imported by `setu_ai_import_guard`, 38 tests, geo +
embedding dedup, explainability, voice). The root `setu_ai_service/` was a strictly older,
unimported copy (`check_duplicate(message, emergency_id)` with no geo; empty `test_models.py`
and `incident_data.json`). It is **removed from git** (history retains it) and ignored via
`.gitignore`. Its **working-tree copy is read-only (`dr-xr-xr-x`) and was left in place**, together
with its untracked `.env`; delete with `chmod -R u+w setu_ai_service && rm -rf setu_ai_service`
when convenient. `tests/test_ai_canonical.py` guards against a second tree returning.

## 14. Tests — exact commands and results (this environment)
Environment: Python 3.14.4 venv outside the repo; `requirements.txt` minus `openai-whisper` and
`sentence-transformers`; SQLite (no PostgreSQL available); Flutter 3.44.8; Node 24.21.
| Command | Result |
|---|---|
| `cd Backend && env -u DATABASE_URL pytest -q` | **322 passed**, 0 failed (baseline 89/93) |
| `cd Backend/setu_ai_service && pytest -q` | **38 passed** |
| `cd setu_app && flutter test` | **185 passed**, 0 failed (includes 38 in the new `backend_contract_test.dart` and 2 new cases in `block1_mesh_test.dart`) |
| `cd setu_app && flutter analyze` | 13 `info`, 0 warnings, 0 errors (none new of consequence: 2 `prefer_initializing_formals` in files touched) |
| `cd setu_dashboard && npm test` | 4 passed |
| `cd setu_dashboard && npm run build` | built OK (existing chunk-size warning) |
| `python tools/cross_lang/verify_python.py <dart-exported dir>` | PASS (Block 1 vector still verifies) |
| `npm audit` | 2 high, both **transitive dev** deps (`js-yaml`, `nanoid`) — not fixed, unrelated to the backend contract |
| `npx eslint …` | **PRE-EXISTING** config error (`eslint.config.js` reads `.recommended` of undefined) — not touched |

Test files: `test_ingest_contract`, `test_request_auth`, `test_dedup_safety`, `test_dashboard_contract`,
`test_abuse_controls`, `test_input_robustness`, `test_e2e_contract`, `test_request_signing_vectors`,
`test_ai_canonical` (+ updated existing ones); Dart `backend_contract_test`, `block1_mesh_test`;
`setu_dashboard/tests/contract.test.mjs`.
CI: `.github/workflows/setu-ci.yml` gained a `backend-and-dashboard-tests` job — **never run on a
GitHub runner**.

## 15. End-to-end contract (VERIFIED)
`test_e2e_contract.py` sends **real Dart-produced wire packets**
(`docs/backend/contract/dart_wire/`, exported by `cross_language_signature_test.dart`, unicode +
`|` + quote in the message) through validation → signature → identity → incident → AI → response,
and checks backend state, database truth and (via `ingest_scenarios.json`, consumed by the real
Dart `classifyIngestResponse`) the mobile-derived state agree for: accepted, duplicate, relayed
copy (=duplicate), 9 tampered variants (all rejected, nothing stored/altered), stale (then
accepted when fresh), packet-ID collision, voice, nearby, community respond, dashboard view,
unauthorized→authorized termination→resolution→closed everywhere, and ack/alert never accepted.

## 16. Remaining limitations (not fixed; nothing hidden)
1. Everything in §5–§12 marked KNOWN LIMITATION / UNTESTED.
2. **PostgreSQL untested.** The identity-index upgrade (`upgrade_raw_packet_identity`) is tested on
   SQLite only; the advisory-lock concurrency path is unchanged and still SQLite-untestable. Run
   the upgrade against a copy of the real database first.
3. `emergency_id` is not sender-scoped in the frozen spec: terminations close *every* incident
   sharing it; AI merge resolution takes the earliest packet with that id.
4. A termination that arrives before its emergency is an accepted no-op (pre-existing).
5. `rejected_packets` has no retention job (bounded only by rate limits); `signed_request_nonces`
   is pruned opportunistically.
6. Registration now 422s when any emergency contact is not a 7–15-digit phone number — one odd
   entry blocks the whole profile sync (and therefore backend SMS/nearby for that user).
7. Root `Backend/debug_*.py`, `send_test_packet.py` are stale helper scripts (some call functions
   that no longer exist); untouched and unverified against the new contract.
8. Sender identities are self-issued keys: no control here can stop an attacker who mints keys
   beyond the rate limits.
9. No device verification of anything.
