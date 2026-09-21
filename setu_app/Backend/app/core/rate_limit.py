"""
Lightweight, dependency-free per-IP rate limiting.

WHY NOT A LIBRARY: adding slowapi/redis (or any new dependency) inside
this session is unverifiable -- no way to pip install and actually run
it here (see the session's own verification notes). A single-process
in-memory sliding window is a real, if modest, control: it stops a
single client from hammering an endpoint from one IP, which is exactly
the T3 (Malicious Internet Client) brute-force/enumeration case this
covers. It does NOT stop a distributed attack across many IPs -- that
needs an edge/WAF layer, which is a deployment concern, not something
to fake here.

DESIGN, matching the session brief's own categories:
  AUTH (request-otp, verify-otp)  -> strict
  RESPONDER ACTION (write routes) -> strict
  PUBLIC WRITE (unauthenticated citizen-facing writes, e.g.
    POST /alerts/{id}/respond) -> lenient. This is NOT emergency
    ingestion (that's /ingest, left uncapped -- see below); it's a
    community "I'm safe" / "on my way" style action. It still needs
    SOME ceiling since it's unauthenticated and writes a DB row per
    call (spam/flood risk), but the ceiling must sit far above any
    real citizen's usage pattern (a person clicks this once or twice
    per incident, not in a loop) so a slow client, retry-on-timeout,
    or a shaky disaster-time connection never gets a real user
    blocked.
  everything else (mesh /ingest, /register, public reads)  -> UNCHANGED,
    deliberately not rate-limited here. The brief is explicit: rate
    limiting must not break emergency ingestion, and /ingest already has
    its own bound via PacketBatchIn.packets' new max_length (see
    schemas/packet.py) plus signature/duplicate/TTL rejection. A global
    limiter in front of the one endpoint that MUST keep working under
    disaster load is a worse trade than leaving it uncapped here.

FAIL-OPEN: any internal error in the limiter allows the request through
rather than blocking it. A bug in rate limiting must never become a
second way to deny service to a legitimate emergency responder action.

MULTI-WORKER CAVEAT, stated plainly: this dict lives in one process's
memory. Behind multiple Uvicorn/Gunicorn workers, each worker enforces
its own independent limit, so the EFFECTIVE limit is (per-worker limit x
worker count) -- looser than the configured number, never stricter. That
is an accepted, documented limitation of an in-memory limiter, not a
silent gap; a real production deployment behind multiple workers should
move this to Redis (see docs/SECURITY_SCORECARD.md).
"""

import time
from collections import defaultdict, deque
from typing import Deque, Dict, Tuple

from fastapi import HTTPException, Request


class InMemoryRateLimiter:
    def __init__(self, max_requests: int, window_seconds: float):
        self.max_requests = max_requests
        self.window_seconds = window_seconds
        self._hits: Dict[str, Deque[float]] = defaultdict(deque)

    def _client_key(self, request: Request) -> str:
        # X-Forwarded-For is attacker-controllable in general, but this
        # backend sits behind Render's own proxy in practice, and the
        # alternative (request.client.host) is just "the proxy" for
        # every request when deployed -- neither is perfect without
        # knowing the exact deployment's trusted-proxy chain. Preferring
        # the first XFF hop is the common pragmatic choice; documented
        # as a known limitation rather than presented as airtight.
        forwarded = request.headers.get("x-forwarded-for")
        if forwarded:
            return forwarded.split(",")[0].strip()
        client = request.client
        return client.host if client else "unknown"

    def check(self, request: Request) -> None:
        try:
            key = self._client_key(request)
            now = time.monotonic()
            hits = self._hits[key]

            while hits and now - hits[0] > self.window_seconds:
                hits.popleft()

            if len(hits) >= self.max_requests:
                retry_after = max(0, self.window_seconds - (now - hits[0]))
                raise HTTPException(
                    status_code=429,
                    detail="Too many requests. Please slow down and try again shortly.",
                    headers={"Retry-After": str(int(retry_after) + 1)},
                )

            hits.append(now)
        except HTTPException:
            raise
        except Exception:
            # Fail open -- see module docstring.
            return

    def reset(self) -> None:
        """Test-only: clears all tracked clients between test cases."""
        self._hits.clear()


# AUTH: strict. 10 requests / 5 minutes per IP across OTP request+verify
# combined is generous for a genuine user (who needs at most 1-2 of
# each) while meaningfully slowing a brute-force attempt against the
# 6-digit code (which otp_service.py already caps at 5 attempts per
# code server-side -- this is a second, IP-level layer on top of that).
auth_rate_limiter = InMemoryRateLimiter(max_requests=10, window_seconds=300)

# RESPONDER ACTION: strict. Provisioning a responder / any future
# privileged write is rare in normal operation; 20 requests/minute per
# IP is far above legitimate dashboard usage and low enough to blunt a
# credential-stuffing attempt against verify_responder_api_key.
responder_action_rate_limiter = InMemoryRateLimiter(max_requests=20, window_seconds=60)

# PUBLIC WRITE: lenient. 30 requests/minute per IP is far above any real
# citizen's usage (a handful of taps per incident) while still bounding
# an unauthenticated write endpoint against scripted spam/flood of the
# CommunityResponse table. Deliberately much looser than the auth/
# responder-action tiers above -- this is not a privileged action.
public_write_rate_limiter = InMemoryRateLimiter(max_requests=30, window_seconds=60)


def enforce_auth_rate_limit(request: Request) -> None:
    auth_rate_limiter.check(request)


def enforce_responder_action_rate_limit(request: Request) -> None:
    responder_action_rate_limiter.check(request)


def enforce_public_write_rate_limit(request: Request) -> None:
    public_write_rate_limiter.check(request)
