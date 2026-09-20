# SETU Security Threat Model

Produced during the Sep 2026 security + production-hardening sprint. Covers
the mesh transport (Flutter + native Kotlin), the FastAPI backend, and the
React dashboard as one system. This is a design-time threat model, not a
penetration-test report — no external scanning or exploitation was
performed (see `docs/SECURITY_SCORECARD.md` for what was/wasn't run).

## Threat actors

| ID | Actor | Access | Motivation |
|----|-------|--------|------------|
| T1 | Malicious mesh peer | A phone running a modified/rogue SETU client, physically near real devices | Disrupt relay, inject false emergencies, deny service, deanonymize |
| T2 | Passive mesh eavesdropper | Any BLE/Wi-Fi Direct listener in range | Harvest location/emergency data broadcast in the clear by design (this is a public safety broadcast protocol, not a confidential channel) |
| T3 | Malicious internet client | Anyone who can reach the backend's public HTTPS endpoints | Flood `/ingest`, enumerate OTP codes, spam `/alerts/{id}/respond`, scrape incident data |
| T4 | Compromised/rogue responder | Holds a real, valid `X-API-Key` (leaked, phished, or an insider) | Read citizen profile/medical data, falsely resolve incidents, register a rogue responder key |
| T5 | Compromised dashboard client | XSS or a malicious browser extension running in a responder's browser session | Steal the `X-API-Key` embedded in the dashboard bundle, act as that responder |
| T6 | Supply-chain / dependency attacker | Anyone who can push a malicious version of a dependency SETU pulls in | Backdoor the app/backend/dashboard at build time |
| T7 | Malicious AI input | Anyone who can get attacker-controlled text into an emergency `message` field that reaches `setu_ai_service`/Gemini | Prompt-injection to mislabel/suppress a real incident, or to poison the AI-driven duplicate-detection now used as dedup's source of truth |

## Assets

- Citizen emergency reports (location, message, medical profile fields)
- Responder identity (Ed25519 keypairs; the backend's shared `X-API-Key`)
- Incident/audit data in Postgres
- The dashboard's embedded `X-API-Key` (shipped in the built JS bundle)
- Mesh relay availability itself (a DoS on relay is a DoS on the emergency
  channel, not just an inconvenience)
- SMTP/SMS gateway credentials used to actually notify people

## Threat → control matrix

### T1 — Malicious mesh peer

| Threat | Existing control | New control (this sprint) | Residual risk |
|---|---|---|---|
| Forge a packet from another sender | Ed25519 signature over packet fields, verified before relay/accept | — (preserved as-is) | Signature payload excludes `ttl`/`hop_count` by design (mutate per hop) — confirmed this is intentional, not an oversight, and left unchanged per the sprint brief |
| Replay an old signed packet | Nonce cache + `maxPacketAge` (5 min) + `allowedClockSkew` (30s) | — (preserved) | None new |
| Flood the mesh with duplicate/near-duplicate packets to drain battery/bandwidth | Seen-cache dedup (LRU, cap 500) | Jittered duplicate-storm suppression in `MeshForegroundService`, `recentEchoCount` tracking in `PacketRelayEngine` | Cap is per-device in-memory; a coordinated multi-peer flood across many distinct packet IDs is only bounded by TTL/hop limits and queue caps, not fully eliminated |
| Impersonate a responder to send a fake `TerminationPacket` | `sender_id` checked against `/responders/keys` (public-key allowlist, polled every 5 min) | — (preserved) | A device that hasn't synced keys recently fails open with a warning (documented existing behavior, not changed) |
| Exhaust a peer's relay queue (queue-based DoS) | `MeshConstants.maxRelayQueue` (bounded) | `PriorityRelayQueue` now tiers by priority so a flood of LOW-priority junk can't starve CRITICAL packets | None new |

### T2 — Passive mesh eavesdropper

| Threat | Existing control | New control | Residual risk |
|---|---|---|---|
| Read emergency location/content over the air | **None — by design.** SETU is a public safety broadcast, not an encrypted channel | Not addressed this sprint (would require a protocol change out of scope — the brief explicitly says preserve the wire protocol absent a proven need) | **Accepted risk, not a bug**: anyone in BLE/Wi-Fi Direct range can observe emergency broadcasts. This should be stated plainly in any user-facing privacy notice. |

### T3 — Malicious internet client

| Threat | Existing control | New control | Residual risk |
|---|---|---|---|
| Brute-force the 6-digit email OTP | Per-code attempt cap (`MAX_OTP_ATTEMPTS`), single-use, expiry | IP-level `auth_rate_limiter` (10 req/5min) on both OTP routes | Distributed (many-IP) brute force still only rate-limited per IP, per the documented multi-worker/single-process caveat |
| Flood `/ingest` to exhaust backend resources | Signature verification, nonce/replay checks, TTL bounds, per-batch packet cap (new: `PacketBatchIn.packets` max 500) | New: every `PacketIn` field now has an explicit length/range bound (was previously unbounded strings/floats) | `/ingest` is deliberately left un-rate-limited (see `rate_limit.py` docstring) — this is an accepted trade favoring emergency availability over flood resistance; the per-field bounds and existing crypto checks are the actual mitigation |
| Spam the public `POST /alerts/{id}/respond` endpoint | None previously | New: `enforce_public_write_rate_limit` (30 req/min/IP) | Legitimate bursty use (e.g. many citizens responding to the same incident from behind one NAT/IP) shares the same per-IP bucket — documented trade-off, deliberately lenient |
| Provision a rogue responder / guess an API key via scripted requests | Static shared `X-API-Key`, `hmac.compare_digest` (new — was `!=`) | New: `enforce_responder_action_rate_limit` (20 req/min/IP) on `POST /responders` and `POST /incidents/{id}/resolve`; new: fail-fast startup check refusing to boot with the default dev key when `debug=False` | A leaked real key still fully authorizes — the shared-key model itself is a known architectural limitation (see T4) |
| Send an oversized request body to any route | None previously | New: global `limit_request_body_size` middleware (413 above 30MB), on top of `voice.py`'s existing ~25MB cap | Content-Length spoofing to *under*-report a larger streamed body is not separately defended by this middleware alone — relies on Starlette/Uvicorn's own body-size handling for chunked transfer |
| Cross-origin request from an untrusted site | `CORSMiddleware` with an explicit origin allow-list (not `*`) | — (verified already correct, not modified) | `allow_methods=["*"]`/`allow_headers=["*"]` are broader than strictly needed; left unchanged this sprint since narrowing them without the ability to test against the real dashboard risks breaking it (see Known Gaps) |

### T4 — Compromised/rogue responder

| Threat | Existing control | New control | Residual risk |
|---|---|---|---|
| Read citizen profile/medical data via a leaked key | `verify_responder_api_key` on every profile-returning route | New: `hmac.compare_digest` closes the timing side-channel that could narrow key-guessing | **Architectural**: one shared key for all responders means there is no per-responder revocation or audit trail of *which* responder read what — flagged, not fixed (would be a real design change, out of scope for a hardening pass) |
| Falsely mark an incident resolved | Same API key | New: rate-limited | Same shared-key limitation applies |
| Register a rogue responder key | Same API key | New: rate-limited (heaviest tier) | Same shared-key limitation applies — anyone holding the one key can add another "trusted" responder key that mesh devices will then honor for terminations |

### T5 — Compromised dashboard client (XSS/extension)

| Threat | Existing control | New control | Residual risk |
|---|---|---|---|
| Steal the `X-API-Key` from the bundle/runtime | No `dangerouslySetInnerHTML` found in `setu_dashboard/src` (verified by grep); key lives in `VITE_API_KEY`, baked into the built JS, not `localStorage` | Not modified this sprint | The key is **always** present in the shipped JS bundle regardless of XSS — anyone who can read the deployed bundle (not just an XSS victim) can extract it. This is inherent to a build-time-embedded shared key in a public SPA and is a real, unresolved exposure (see Known Gaps / Scorecard) |
| CSRF against a state-changing dashboard action | Dashboard actions require the `X-API-Key` header (not a cookie), which a cross-site form/script can't attach without already having the key | — | Low risk given the header-based (non-cookie) auth model |

### T6 — Supply-chain / dependency attacker

| Threat | Existing control | New control | Residual risk |
|---|---|---|---|
| A malicious/vulnerable dependency ships in the app/backend/dashboard | Pinned versions in `requirements.txt`; `package.json` uses caret ranges | Not addressed — no `pip-audit`/`npm audit`/`flutter pub outdated` could be run in this sandbox (no network access to install them, no SDKs present) | **NOT VERIFIED**, not "clean" — see `docs/SECURITY_SCORECARD.md`. Brief explicitly forbade blind mass upgrades without ability to test, so none were attempted. |

### T7 — Malicious AI input (prompt injection / dedup poisoning)

| Threat | Existing control | New control | Residual risk |
|---|---|---|---|
| Craft a `message` string that manipulates Gemini/the embedding pipeline into misclassifying incident type/urgency | AI output (`ai_incident_type`, `ai_urgency`, etc.) is advisory metadata stored alongside the incident, never used for authorization | Not addressed — no prompt-injection defenses in `setu_ai_service` were added this sprint (out of scope: would require changes inside the vendored AI service, and no way to test Gemini behavior in this sandbox) | **Real, undefended risk, newly documented**: per `ai_analysis_service.py`'s own docstring, the team *reversed* an earlier decision and now uses the AI's `is_duplicate`/`matched_cluster_id` as the **dedup source of truth**. A crafted message that convinces the AI a new, genuine emergency is a duplicate of an old one would cause it to be silently merged rather than creating a new incident — an availability/integrity risk on the emergency pipeline itself, not just an AI-quality issue. Flagged as **HIGH-priority follow-up** in the Scorecard; not fixed in this sprint (no safe way to validate a fix without a live AI service to test against). |

## Explicitly out of scope this sprint (and why)

- Rewriting the shared-responder-API-key model to per-responder credentials — a real architecture change, not a hardening patch; needs a team decision per the brief's own instructions.
- Narrowing CORS `allow_methods`/`allow_headers` from `*` — can't be verified against the live dashboard in this sandbox; changing it blind risks breaking legitimate dashboard requests.
- Changing the mesh wire protocol / signature payload fields — the brief explicitly says preserve intentional exclusions (ttl/hop_count) unless proven necessary; no such proof was produced.
- Adding prompt-injection defenses inside `setu_ai_service` — vendored third-party-owned code, no test harness available here.
