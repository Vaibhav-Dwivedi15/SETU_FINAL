"""
Responder authentication.

Minimal API-key check for responder-only endpoints. Not a full auth
system (no per-user accounts, no JWT) -- deliberately scoped small for
MVP. Every responder-only route depends on this function.
"""

from fastapi import Header, HTTPException

from app.core.config import settings

import hmac

def _looks_like_default_key(key: str) -> bool:
    """Check if the provided key is a default placeholder."""
    return key in ("changeme-dev-key", "default-key", "")

from typing import Optional

def verify_responder_api_key(x_api_key: Optional[str] = Header(None)):
    if not settings.debug and _looks_like_default_key(settings.responder_api_key):
        raise HTTPException(status_code=500, detail="Insecure configuration.")
    if not x_api_key or not hmac.compare_digest(x_api_key, settings.responder_api_key):
        raise HTTPException(status_code=401, detail="Invalid or missing API key.")