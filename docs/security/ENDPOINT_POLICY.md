# Endpoint access policy (Block 3)

Enforced and gated by `Backend/tests/test_endpoint_policy.py`: every route must be classified below,
each class is exercised, and an unclassified route fails the test suite.

| Class | Credential | Endpoints |
|---|---|---|
| **PUBLIC** | none (by design) | `GET /`, `GET /health`, `GET /ingest/voice/status`, `GET /responders/keys` (public keys only, polled by mesh devices), `POST /auth/request-otp`, `POST /auth/verify-otp`, `POST /auth/responder-login` (credential *exchange*, rate-limited + brute-force damped) |
| **INGEST** | **Ed25519 packet signature (mandatory)** — no bearer/API key, so an offline-originated SOS can be delivered by any exit node once it has connectivity | `POST /ingest` |
| **DEVICE** | request signed by a device Ed25519 key (`X-Setu-*`, proof of possession, replay-protected) | `POST /register`, `POST /ingest/voice`, `GET /alerts/nearby` (+ registered profile), `POST /alerts/{id}/respond` (+ registered profile) |
| **RESPONDER** | dashboard session token (`Authorization: Bearer`) **or** `X-API-Key: RESPONDER_API_KEY` | `GET /incidents`, `POST /incidents/{id}/resolve`, `GET /incidents/{id}/profile|history|responses|government-notifications`, `GET /government/*`, `GET /responders` |
| **ADMIN** | `X-API-Key: ADMIN_API_KEY` only (a session token never qualifies; unset ⇒ 503) | `POST /responders`, `POST /responders/{public_key}/revoke` |

Design notes
* `/ingest` keeps its different trust model on purpose: authenticity comes from the packet signature
  (checked before dedup; forged/stale/unsigned packets are rejected), not from a login the offline device
  cannot perform. Nothing was added that would block genuine offline traffic.
* Interactive docs (`/docs`, `/redoc`, `/openapi.json`) are disabled unless `DEBUG=true`.
* Responder *trust* for terminations is a separate registry (Ed25519 public keys) that only ADMIN can
  change; a dashboard operator cannot promote a key. Empty registry ⇒ every termination is refused
  (backend and mobile). Revocation drops the key from the next `/responders/keys` sync and from `/ingest` immediately.
* Every API response carries `nosniff`, `no-store`, `no-referrer`, HSTS, `frame-ancestors 'none'`.
* CORS: explicit origin list (`CORS_ALLOWED_ORIGINS_RAW`), no wildcard, no credentials, methods GET/POST/OPTIONS,
  headers `Authorization, Content-Type`. Mobile clients are not browsers and are unaffected.
