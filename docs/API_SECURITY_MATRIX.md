# SETU Backend API Security Matrix

Every route currently registered in `Backend/app/main.py`, as of this
sprint. "Auth" = `verify_responder_api_key` (shared `X-API-Key` header)
unless noted otherwise. "Rate limit" reflects this sprint's additions;
routes not listed as rate-limited are deliberately left uncapped (see
`app/core/rate_limit.py`'s module docstring and the threat model's T3
section for why).

| Method | Path | Auth | Rate limit | Input validation | Notes |
|---|---|---|---|---|---|
| GET | `/` | None | None | — | Static health string, no data |
| GET | `/health/*` (see `health.py`) | None | None | — | `SELECT 1` liveness check, parameterized |
| POST | `/ingest` | None (signature-verified instead) | None (deliberate — see threat model) | Pydantic `PacketIn`, all fields now bounded (this sprint) | Ed25519 signature + nonce/replay + TTL checked before acceptance |
| POST | `/ingest/batch` | None (per-packet signature-verified) | None (deliberate) | Each dict validated individually against `PacketIn`; batch itself capped at 500 (this sprint, was unbounded) | One bad packet doesn't fail the batch, by design |
| POST | `/ingest/voice` | None | None | `python-multipart` file upload, ~25MB cap in `voice.py` | 503s cleanly if Whisper/ffmpeg aren't provisioned |
| GET | `/ingest/voice/status` | None | None | — | Status/health only |
| POST | `/register` | None | None | Pydantic `RegisterIn`, all fields now bounded (this sprint) | Citizen profile registration — intentionally open (first-run, pre-auth). **Unfixed gap this sprint**: no proof-of-possession on `sender_id` (a public value), so anyone who knows a target's `sender_id` can currently overwrite their profile including `medical_history`/`emergency_contacts` — see threat model, second-highest-priority follow-up |
| POST | `/incidents/{id}/resolve` | **X-API-Key** | **20/min/IP (new)** | Path param `int` | Privileged write; idempotent |
| GET | `/incidents` | **X-API-Key** | None | — | List all incidents |
| GET | `/incidents/{id}/profile` | **X-API-Key** | None | Path param `int` | Returns citizen profile/medical data — most sensitive read in the API |
| GET | `/incidents/{id}/history` | **X-API-Key** | None | Path param `int` | Audit trail read |
| POST | `/responders` | **X-API-Key** | **20/min/IP (new)** | Pydantic `ResponderIn` | Most sensitive write — provisions a key trusted mesh-wide for terminations |
| GET | `/responders` | **X-API-Key** | None | — | Lists all responders |
| GET | `/responders/keys` | None (deliberately public) | None | — | Mesh devices poll this to verify termination senders; must stay open |
| GET | `/alerts/nearby` | None (deliberately public) | None | Query params bounded (`lat`/`lon`/`radius_km` all have `ge`/`le`) | Citizen-facing read, no auth by design |
| POST | `/alerts/{id}/respond` | None (deliberately public) | **30/min/IP (new)** | Pydantic `RespondIn`, path param `int` | Only unauthenticated *write* in the API — new rate limit added this sprint |
| GET | `/incidents/{id}/responses` | **X-API-Key** | None | Path param `int` | Responder-facing read |
| POST | `/auth/request-otp` | None (deliberately public — pre-identity) | **10/5min/IP (new)** | Pydantic `OtpRequestIn` | Also has its own resend-cooldown logic in `otp_service.py` independent of this IP limiter |
| POST | `/auth/verify-otp` | None (deliberately public) | **10/5min/IP (new)** | Pydantic `OtpVerifyIn` | Per-code attempt cap (`MAX_OTP_ATTEMPTS`) is separate, existing, and not changed |
| GET | `/incidents/{id}/government-notifications` | **X-API-Key** | None | Path param `int` | Read-only audit log of the mock government adapter |
| GET | `/government/notifications` | **X-API-Key** | None | `limit` query clamped 1–500 server-side | Read-only |
| GET | `/government/adapter-status` | **X-API-Key** | None | — | Read-only; always reports `is_mock` honestly |

## Global controls (apply to every route above)

- **CORS**: explicit origin allow-list via `settings.cors_allowed_origins` (not `*`); `allow_credentials=True`. `allow_methods`/`allow_headers` are `*` — flagged as a gap in the threat model, not changed this sprint (unverifiable against the live dashboard here).
- **Body size**: new global `limit_request_body_size` middleware, 413 above 30MB, on every route (defense-in-depth in front of the per-route Pydantic bounds and `voice.py`'s own tighter cap).
- **Auth comparison**: `verify_responder_api_key` now uses `hmac.compare_digest` (was `!=`) — closes a timing side-channel.
- **Default-key fail-fast**: the app now refuses to boot in non-debug mode if `RESPONDER_API_KEY` is still the placeholder default, instead of silently accepting it as a "working" key.
- **Error handling**: FastAPI's default exception handling returns generic 4xx/5xx JSON; no stack traces or internal paths are echoed to the client in any route inspected (spot-checked `ingest.py`, `incidents.py`, `auth.py` — all raise `HTTPException` with a fixed `detail` string, never `str(exc)` of an internal exception, into the response body). Exceptions are logged server-side via `logger.exception(...)` (see e.g. `ai_analysis_service.py`), not returned to the caller.

## Known gaps (documented, not fixed this sprint — see threat model for why)

- **`POST /register` has no proof-of-possession check on `sender_id`** — a public value, not a secret. Highest-priority *unfixed* gap in this file (see threat model).
- Shared single `X-API-Key` for all responders (no per-responder identity/revocation).
- `allow_methods`/`allow_headers` on CORS are `*`.
- `/ingest`, `/ingest/batch`, `/register`, `/alerts/nearby`, `/responders/keys` remain unrate-limited by deliberate design choice, not oversight.
- No WAF/CDN-level protection against distributed (multi-IP) flooding — the in-memory limiter is single-process and per-IP only.
