# SETU Security Architecture

How identity, trust, and authorization actually work across the three
tiers, as verified by reading the real implementation this sprint (not
assumed from naming or comments — several stale comments elsewhere in the
codebase describe things that are no longer true, e.g. signature
verification once being called a "stub" when it is a real Ed25519
implementation).

## 1. Identity model

SETU has **two independent identity systems** that must not be conflated:

1. **Device identity (mesh-native, cryptographic)**: every device generates
   an Ed25519 keypair. `sender_id` on every packet IS the hex-encoded
   public key — self-certifying, no registry lookup needed to verify a
   signature (`app/services/signature_service.py`). This is the sole
   cryptographic basis for anything security-relevant in the mesh path.
2. **Responder identity (backend-native, key-list)**: a separate table of
   `ResponderProfile` rows, each with its own `public_key`, exposed
   publicly at `GET /responders/keys`. Mesh devices poll this list to
   decide whether a `TerminationPacket`'s `sender_id` belongs to a
   trusted responder before honoring it client-side. This list is
   provisioned via the backend's shared `X-API-Key`-gated `POST
   /responders` — a *third*, weaker credential (see below) gates who can
   add to this trusted list.
3. **Backend API credential (shared secret, not identity)**: a single
   `RESPONDER_API_KEY` value, checked via `X-API-Key` header
   (`verify_responder_api_key`), gates every dashboard-facing read/write
   in the backend. This is **not** per-responder — it does not identify
   *which* responder made a request, only that *some* holder of the one
   key did. Email OTP (`/auth/*`) is a fourth, separate mechanism that
   confirms a human controls an email address at registration time; it
   issues no token and gates nothing else (explicitly documented in
   `auth.py`'s own module docstring).

**Do not conflate these.** A leaked backend API key does not compromise
any device's Ed25519 private key, and vice versa. But a leaked backend API
key *does* let an attacker call `POST /responders` to add a new
"trusted" public key that real mesh devices will then honor for
terminations — the backend key is a real bridge between the two systems.

## 2. Trust boundaries

```
[Citizen phone]  --BLE/Wi-Fi Direct, unencrypted, signed packets-->  [Mesh peers]
      |                                                                    |
      | (eventually, when connectivity returns)                          relay
      v                                                                    v
[POST /ingest, HTTPS]  <-------------------------------------------  [Exit node phone]
      |
      v
 [FastAPI backend] --X-API-Key--> [Dashboard, responder browser]
      |
      +--SMTP--> [Citizen email, OTP]
      +--HTTPS--> [SMS Gateway for Android, Ayush's phone]
      +--in-process call--> [setu_ai_service / Gemini, advisory only]
```

- The mesh segment (top) is **untrusted by design** — any packet's
  authenticity rests entirely on its Ed25519 signature, never on which
  peer relayed it (`hop_count`/`relay_path` are metadata, not trust
  signals).
- `/ingest` is the one HTTP boundary every mesh packet eventually crosses.
  It re-validates signature, nonce/replay, and (this sprint) field bounds
  independently of anything the mesh layer already checked — a
  compromised or buggy mesh client cannot bypass backend-side validation
  by skipping the app-layer checks.
- The dashboard is a **public SPA with an embedded shared secret**. This
  is architecturally different from a normal per-user session model:
  anyone who can read the deployed JS bundle can extract
  `VITE_API_KEY`. This is a known, unresolved trust-boundary weakness
  (see Threat Model T5) — acceptable for a hackathon-scale demo, flagged
  explicitly as not production-ready.
- `setu_ai_service` (Gemini-backed) sits **inside** the trust boundary for
  availability (a failure never blocks ingestion — `analyze()` always
  returns `None` on error, never raises) but, per the reversed dedup
  decision in `ai_analysis_service.py`, its `is_duplicate`/
  `matched_cluster_id` output now has real effect on whether a report
  becomes a new incident. It is advisory for classification but **not
  fully advisory for dedup** — see Threat Model T7.

## 3. Data classification

| Data | Where it lives | Sensitivity | Exposure path |
|---|---|---|---|
| Ed25519 private keys | On-device only (never transmitted) | Critical | Device compromise only |
| `X-API-Key` (responder) | Backend env var + dashboard build bundle | High | Bundle extraction (always possible), env leak |
| Citizen profile (name, age, medical history) | Postgres `user_profile` table | High | `GET /incidents/{id}/profile`, gated by the shared key |
| Emergency message/location | Postgres, and broadcast in clear over BLE/Wi-Fi Direct | Medium-High | Radio eavesdropping (accepted, by design) + `/ingest`/`/alerts/nearby` |
| SMTP/SMS gateway credentials | `.env`, not committed (verified this sprint) | High | Server env only |
| Mock government adapter references | Postgres, prefixed `MOCK-GOV-` | Low | Explicitly non-sensitive by design |

## 4. Why the mesh signature payload excludes TTL/hop_count

Confirmed by reading `signature_service.py` directly: the signed payload
is a pipe-separated string built from fields that do NOT change per relay
hop. `ttl` and `hop_count` are mutated by every relaying device
(`withRelayHop()`), so including them in the signed payload would make
every packet's signature invalid after the first hop. This is a correct,
intentional design, not an omission — preserved as-is per the sprint
brief's explicit instruction not to silently change the wire protocol.

## 5. Failure posture summary

| Component | On failure/error | Rationale |
|---|---|---|
| `verify_responder_api_key` | Rejects (fail closed) | Auth must fail closed |
| Mesh signature verification | Rejects (fail closed) | Same |
| `InMemoryRateLimiter.check()` | Allows the request through (fail open) | A limiter bug must never become a second way to deny emergency service |
| `enforce_public_write_rate_limit` / auth / responder-action limiters | Same fail-open behavior | Same reasoning, inherited from the same class |
| `ai_analysis_service.analyze()` | Returns `None`, never raises | AI classification failure must not block ingestion |
| `/responders/keys` sync on the mesh side | Fails open with a warning if unreachable (existing, unchanged) | Documented existing trade-off — availability over strict termination-authorization freshness |
| `limit_request_body_size` middleware | On any internal error in the check itself, allows the request through | Same fail-open principle applied consistently across every new control this sprint |
