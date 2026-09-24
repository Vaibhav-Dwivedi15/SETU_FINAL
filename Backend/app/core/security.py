"""
Responder authentication.

Minimal API-key check for responder-only endpoints. Not a full auth
system (no per-user accounts, no JWT) -- deliberately scoped small for
MVP. Every responder-only route depends on this function.

SEP 2026 SECURITY HARDENING (two fixes, both additive -- the API-key
model itself is unchanged):

1. Comparison was `x_api_key != settings.responder_api_key`, a
   Python `!=` on strings, which short-circuits on the first mismatched
   byte. That makes the comparison time a (very small, but real) side
   channel: an attacker who can measure response timing precisely
   enough can in principle recover the key one byte at a time. Fixed
   with `hmac.compare_digest`, which always takes the same time
   regardless of where the strings first differ. Same reasoning already
   applied to OTP verification in otp_service.py -- this brings the
   responder key check to the same standard.

2. `Settings.responder_api_key` defaults to the literal string
   "changeme-dev-key" (see core/config.py) so the app still boots for
   local development without a .env file. That default is exactly the
   kind of thing that ships to production by accident: if RENDER (or
   wherever this is deployed) never had RESPONDER_API_KEY set, every
   responder-only endpoint -- including TERMINATION authorization and
   the responder registry -- would silently accept that well-known
   string as a valid credential. `_looks_like_default_key()` is checked
   at first use (not at import time, so tests that override
   settings.responder_api_key directly are unaffected) and raises
   loudly rather than accepting the request, but ONLY when
   settings.debug is False -- local/dev boots with the placeholder are
   expected and must not be blocked.
"""

import hmac
from typing import Optional

from fastapi import Header, HTTPException, Request

from app.core.config import settings
from app.core.rate_limit import api_key_failure_limiter
from app.services.session_service import Principal, ROLE_RESPONDER, verify_token

_DEFAULT_KEY_MARKER = "changeme-dev-key"


def _looks_like_default_key() -> bool:
    return settings.responder_api_key == _DEFAULT_KEY_MARKER


def _key_matches(presented: Optional[str], configured: str) -> bool:
    if not presented or not configured:
        return False
    return hmac.compare_digest(presented.encode("utf-8"), configured.encode("utf-8"))


def _deny(request: Request, status: int = 401, detail: str = "Invalid or missing credentials.") -> HTTPException:
    api_key_failure_limiter.record(request)
    return HTTPException(status_code=status, detail=detail, headers={"WWW-Authenticate": "Bearer"} if status == 401 else None)


def verify_responder_api_key(
    request: Request,
    x_api_key: Optional[str] = Header(default=None),
    authorization: Optional[str] = Header(default=None),
) -> Principal:
    """
    RESPONDER-role gate (name kept: every route already depends on it). Accepts EITHER

      * `Authorization: Bearer <session token>` from POST /auth/responder-login
        (what the dashboard uses -- no key in the browser bundle), or
      * `X-API-Key: <RESPONDER_API_KEY>` (server-side scripts / curl only).

    Returns the authenticated Principal. Failures count toward a per-IP brute-force
    damper (429 after 20/min).
    """
    if api_key_failure_limiter.is_blocked(request):
        raise HTTPException(status_code=429, detail="Too many failed authentication attempts.")

    if isinstance(authorization, str) and authorization:  # (a Header default when called directly)
        scheme, _, token = authorization.partition(" ")
        principal = verify_token(token.strip()) if scheme.lower() == "bearer" else None
        if principal is None:
            raise _deny(request, detail="Invalid or expired session.")
        return principal

    if not settings.debug and (_looks_like_default_key() or not settings.responder_api_key):
        # Misconfiguration, not a client error: refuse to authenticate against a
        # well-known / empty placeholder credential.
        raise HTTPException(
            status_code=500,
            detail=(
                "Server misconfiguration: RESPONDER_API_KEY was never set "
                "and DEBUG is false. Refusing to authenticate against the "
                "default placeholder key."
            ),
        )

    if _key_matches(x_api_key, settings.responder_api_key) or (
        settings.admin_api_key and _key_matches(x_api_key, settings.admin_api_key)
    ):
        return Principal(role=ROLE_RESPONDER, session_id="api-key")
    raise _deny(request, detail="Invalid or missing API key.")


def verify_admin_api_key(request: Request, x_api_key: Optional[str] = Header(default=None)) -> Principal:
    """
    ADMIN-role gate (provision / revoke trusted responder signing keys). Header key
    only -- a dashboard session token can NEVER satisfy this, so a dashboard user
    cannot promote a key to responder. Fail closed: with ADMIN_API_KEY unset the
    endpoint is unavailable (503) rather than falling back to the responder key
    (outside DEBUG).
    """
    if api_key_failure_limiter.is_blocked(request):
        raise HTTPException(status_code=429, detail="Too many failed authentication attempts.")
    configured = settings.admin_api_key
    if not configured:
        if settings.debug:
            configured = settings.responder_api_key  # local development convenience only
        else:
            raise HTTPException(status_code=503, detail="Admin operations are disabled: ADMIN_API_KEY is not configured.")
    if not _key_matches(x_api_key, configured):
        raise _deny(request, detail="Invalid or missing admin key.")
    return Principal(role="admin", session_id="admin-key")
