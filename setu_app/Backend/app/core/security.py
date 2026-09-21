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

from fastapi import Header, HTTPException

from app.core.config import settings

_DEFAULT_KEY_MARKER = "changeme-dev-key"


def _looks_like_default_key() -> bool:
    return settings.responder_api_key == _DEFAULT_KEY_MARKER


def verify_responder_api_key(x_api_key: str = Header(...)):
    if not settings.debug and _looks_like_default_key():
        # Fail loudly and safely: reject every request rather than
        # accept a well-known placeholder credential in what looks like
        # a production boot. This is a misconfiguration, not a client
        # error, so 500 (not 401) is the honest status -- the operator
        # needs to set RESPONDER_API_KEY, the caller did nothing wrong.
        raise HTTPException(
            status_code=500,
            detail=(
                "Server misconfiguration: RESPONDER_API_KEY was never set "
                "and DEBUG is false. Refusing to authenticate against the "
                "default placeholder key."
            ),
        )

    if not hmac.compare_digest(x_api_key, settings.responder_api_key):
        raise HTTPException(status_code=401, detail="Invalid or missing API key.")