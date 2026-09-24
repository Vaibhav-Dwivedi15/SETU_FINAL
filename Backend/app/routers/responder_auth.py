"""
POST /auth/responder-login -- exchange the responder key (typed by a human operator,
never bundled into the dashboard JavaScript) for a short-lived bearer session.
See services/session_service.py for the token design and limits.
"""

import hmac

from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel, Field

from app.core.config import settings
from app.core.rate_limit import api_key_failure_limiter, auth_rate_limiter
from app.services.session_service import SessionsUnavailable, issue_token

router = APIRouter()


class LoginIn(BaseModel):
    key: str = Field(..., min_length=1, max_length=256)


class LoginOut(BaseModel):
    access_token: str
    token_type: str = "Bearer"
    expires_in: int


@router.post("/auth/responder-login", response_model=LoginOut)
def responder_login(payload: LoginIn, request: Request):
    auth_rate_limiter.check(request)  # 10 / 5 min / IP, same tier as OTP
    if api_key_failure_limiter.is_blocked(request):
        raise HTTPException(status_code=429, detail="Too many failed authentication attempts.")

    configured = settings.responder_api_key
    if not settings.debug and (not configured or configured == "changeme-dev-key"):
        raise HTTPException(status_code=500, detail="Server misconfiguration: RESPONDER_API_KEY is not set.")

    if not configured or not hmac.compare_digest(payload.key.encode("utf-8"), configured.encode("utf-8")):
        api_key_failure_limiter.record(request)
        raise HTTPException(status_code=401, detail="Invalid credentials.")

    try:
        token, ttl = issue_token()
    except SessionsUnavailable:
        raise HTTPException(status_code=503, detail="Sessions are disabled: SESSION_SECRET (>=32 chars) is not configured.")
    return LoginOut(access_token=token, expires_in=ttl)
