"""
Abuse controls: per-endpoint sliding-window rate limits, safe client-IP
extraction, and (in core/body_limit.py) a byte-counting body-size cap.

Dependency-free and in-process on purpose (no Redis in this stack). What that
does and does not give you -- stated plainly:

  * It bounds a single client / single key on one process. Behind N workers the
    effective limit is N x the configured one (each worker counts separately).
    A distributed flood needs an edge/WAF layer or a shared store.
  * State is BOUNDED: at most `max_keys` tracked keys per limiter; stale keys
    are pruned and the least-recently-seen evicted, so the limiter cannot be
    used to exhaust memory by rotating identities.

CLIENT IP (Block 2 fix): `X-Forwarded-For` is client-controlled, so it is only
honoured for as many hops as `settings.trusted_proxy_count` says are real
proxies, taking the entry that the OUTERMOST trusted proxy appended (N-th from
the right). Anything a client prepends is never used. With 0 trusted proxies
only the socket peer counts.

FAILURE POSTURE (Block 2 fix): each limiter states what happens if its own
state handling errors:
  * fail_open=True  -- emergency-critical paths (/ingest, /responders/keys): a
    limiter bug must never block an SOS.
  * fail_open=False -- abuse-sensitive paths (register, voice, nearby, auth,
    responder actions): answer 503 rather than run unmetered.

EMERGENCY TRAFFIC: /ingest limits are per IP and deliberately far above one
device's behaviour (a device uploads a handful of packets; a shared carrier IP
may front hundreds of devices). Exceeding them yields 429, which the mobile
client treats as "not delivered, retry later" -- packets are never lost.
"""

import ipaddress
import time
from collections import OrderedDict, deque
from typing import Deque, List, Optional, Tuple

from fastapi import HTTPException, Request

from app.core.config import settings

ALL_LIMITERS: List["InMemoryRateLimiter"] = []


def client_ip(request: Request) -> str:
    peer = request.client.host if request.client else "unknown"
    proxies = settings.trusted_proxy_count
    if proxies <= 0:
        return peer
    forwarded = request.headers.get("x-forwarded-for", "")
    parts = [p.strip() for p in forwarded.split(",") if p.strip()]
    if len(parts) < proxies:
        return peer  # fewer hops than trusted proxies: header is not from our proxy chain
    candidate = parts[-proxies]
    try:
        return str(ipaddress.ip_address(candidate))
    except ValueError:
        return peer


class InMemoryRateLimiter:
    def __init__(self, name: str, max_requests: int, window_seconds: float,
                 fail_open: bool = False, max_keys: int = 20000):
        self.name = name
        self.max_requests = max_requests
        self.window_seconds = window_seconds
        self.fail_open = fail_open
        self.max_keys = max_keys
        # key -> (deque[(timestamp, cost)], running_total)
        self._hits: "OrderedDict[str, Tuple[Deque[Tuple[float, int]], int]]" = OrderedDict()
        ALL_LIMITERS.append(self)

    # -- core -------------------------------------------------------------
    def _prune(self, now: float, key: str) -> Tuple[Deque[Tuple[float, int]], int]:
        hits, total = self._hits.get(key, (deque(), 0))
        while hits and now - hits[0][0] > self.window_seconds:
            total -= hits.popleft()[1]
        return hits, total

    def _evict_if_needed(self) -> None:
        while len(self._hits) > self.max_keys:
            self._hits.popitem(last=False)  # least recently seen

    def _check_key(self, key: str, cost: int, record: bool = True) -> None:
        now = time.monotonic()
        hits, total = self._prune(now, key)
        if total + cost > self.max_requests:
            oldest = hits[0][0] if hits else now
            retry_after = max(0.0, self.window_seconds - (now - oldest))
            raise HTTPException(
                status_code=429,
                detail="Too many requests. Please slow down and try again shortly.",
                headers={"Retry-After": str(int(retry_after) + 1)},
            )
        if record:
            hits.append((now, cost))
            total += cost
        self._hits[key] = (hits, total)
        self._hits.move_to_end(key)
        self._evict_if_needed()

    def check(self, request: Request, key: Optional[str] = None, cost: int = 1) -> None:
        try:
            self._check_key(key if key is not None else client_ip(request), cost)
        except HTTPException:
            raise
        except Exception:
            if self.fail_open:
                return
            raise HTTPException(status_code=503, detail="Service temporarily unavailable.")

    def is_blocked(self, request: Request) -> bool:
        """Non-recording check (used to gate on prior FAILURES)."""
        try:
            self._check_key(client_ip(request), 1, record=False)
            return False
        except HTTPException:
            return True
        except Exception:
            return not self.fail_open

    def record(self, request: Request) -> None:
        try:
            now = time.monotonic()
            key = client_ip(request)
            hits, total = self._prune(now, key)
            hits.append((now, 1))
            self._hits[key] = (hits, total + 1)
            self._hits.move_to_end(key)
            self._evict_if_needed()
        except Exception:
            pass

    def reset(self) -> None:
        """Test-only: clears all tracked clients between test cases."""
        self._hits.clear()


# AUTH (request-otp, verify-otp): strict. 10 / 5 min per IP.
auth_rate_limiter = InMemoryRateLimiter("auth", 10, 300)
# RESPONDER ACTION (privileged writes): 20 / min per IP.
responder_action_rate_limiter = InMemoryRateLimiter("responder_action", 20, 60)
# PUBLIC WRITE (community respond): lenient, 30 / min per IP.
public_write_rate_limiter = InMemoryRateLimiter("public_write", 30, 60)
# FAILED responder API-key attempts: 20 / min per IP, then 429 (brute-force damper).
api_key_failure_limiter = InMemoryRateLimiter("api_key_failures", 20, 60)

# EMERGENCY INGEST -- fail OPEN, generous.
ingest_request_limiter = InMemoryRateLimiter("ingest_requests", 300, 60, fail_open=True)
ingest_packet_limiter = InMemoryRateLimiter("ingest_packets", 3000, 60, fail_open=True)
# Public registry poll (mesh devices every 5 min): fail open.
responder_keys_limiter = InMemoryRateLimiter("responder_keys", 60, 60, fail_open=True)

# Authenticated-by-signature endpoints: per IP and per sender key (fail closed).
voice_ip_limiter = InMemoryRateLimiter("voice_ip", 10, 60)
voice_sender_limiter = InMemoryRateLimiter("voice_sender", 5, 300)
register_ip_limiter = InMemoryRateLimiter("register_ip", 10, 60)
register_sender_limiter = InMemoryRateLimiter("register_sender", 10, 600)
nearby_ip_limiter = InMemoryRateLimiter("nearby_ip", 60, 60)
nearby_sender_limiter = InMemoryRateLimiter("nearby_sender", 30, 60)


def enforce_auth_rate_limit(request: Request) -> None:
    auth_rate_limiter.check(request)


def enforce_responder_action_rate_limit(request: Request) -> None:
    responder_action_rate_limiter.check(request)


def enforce_public_write_rate_limit(request: Request) -> None:
    public_write_rate_limiter.check(request)


def enforce_responder_keys_rate_limit(request: Request) -> None:
    responder_keys_limiter.check(request)


def enforce_ingest_rate_limit(request: Request, packet_count: int) -> None:
    ingest_request_limiter.check(request)
    ingest_packet_limiter.check(request, cost=max(packet_count, 1))
