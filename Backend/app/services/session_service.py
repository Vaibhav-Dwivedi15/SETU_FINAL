"""
Short-lived dashboard sessions (Block 3) -- replaces shipping the shared responder
API key inside the browser bundle (a Vite env var is public by construction).

Flow: an operator types the responder key into the dashboard login form (it is never
built into the JavaScript) -> POST /auth/responder-login verifies it in constant time and
returns a signed, expiring bearer token -> the dashboard sends `Authorization: Bearer`.
The raw key is not stored by the browser; the token can only do what the "responder"
role may do (read incidents, resolve). It cannot provision responders (ADMIN only, see
core/security.py) and it expires by itself.

Token = base64url(json claims) "." base64url(HMAC-SHA256(SESSION_SECRET, first part)).
Stateless on purpose (no new table / framework): revoke everything by rotating
SESSION_SECRET; individual tokens are bounded by `exp`. Claims: v, role, iat, exp, jti.
"""

import base64
import hashlib
import hmac
import json
import secrets
import time
from dataclasses import dataclass
from typing import Optional

from app.core.config import settings

TOKEN_VERSION = 1
ROLE_RESPONDER = "responder"
MAX_TOKEN_CHARS = 1024


@dataclass
class Principal:
    role: str
    session_id: str  # jti (or "api-key" for header-key callers)


class SessionsUnavailable(Exception):
    """SESSION_SECRET is not configured (and DEBUG is off)."""


def _b64(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")


def _unb64(text: str) -> bytes:
    return base64.urlsafe_b64decode(text + "=" * (-len(text) % 4))


def _secret() -> bytes:
    secret = settings.session_secret
    if not secret:
        if settings.debug:
            return b"insecure-debug-only-session-secret"
        raise SessionsUnavailable()
    if len(secret) < 32:
        # A short secret makes the HMAC guessable; refuse rather than sign with it.
        if settings.debug:
            return secret.encode("utf-8")
        raise SessionsUnavailable()
    return secret.encode("utf-8")


def _sign(part: str) -> str:
    return _b64(hmac.new(_secret(), part.encode("ascii"), hashlib.sha256).digest())


def issue_token(role: str = ROLE_RESPONDER, now: Optional[float] = None) -> tuple[str, int]:
    now = int(now if now is not None else time.time())
    ttl = settings.session_ttl_seconds
    claims = {"v": TOKEN_VERSION, "role": role, "iat": now, "exp": now + ttl, "jti": secrets.token_hex(8)}
    part = _b64(json.dumps(claims, separators=(",", ":")).encode("utf-8"))
    return f"{part}.{_sign(part)}", ttl


def verify_token(token: str, now: Optional[float] = None) -> Optional[Principal]:
    """Principal for a valid, unexpired token; None for anything else (never raises on bad input)."""
    try:
        if not token or len(token) > MAX_TOKEN_CHARS or token.count(".") != 1:
            return None
        part, signature = token.split(".")
        if not hmac.compare_digest(signature.encode("ascii"), _sign(part).encode("ascii")):
            return None
        claims = json.loads(_unb64(part))
        if claims.get("v") != TOKEN_VERSION or claims.get("role") != ROLE_RESPONDER:
            return None
        current = now if now is not None else time.time()
        if not isinstance(claims.get("exp"), int) or claims["exp"] <= current:
            return None
        if claims.get("iat", 0) > current + 60:  # minted in the future: clock games / forgery
            return None
        return Principal(role=claims["role"], session_id=str(claims.get("jti", ""))[:16])
    except SessionsUnavailable:
        return None
    except Exception:
        return None
