"""
Responder authentication.

Minimal API-key check for responder-only endpoints. Not a full auth
system (no per-user accounts, no JWT) -- deliberately scoped small for
MVP. Every responder-only route depends on this function.
"""

from fastapi import Header, HTTPException

from app.core.config import settings


def verify_responder_api_key(x_api_key: str = Header(...)):
    if x_api_key != settings.responder_api_key:
        raise HTTPException(status_code=401, detail="Invalid or missing API key.")