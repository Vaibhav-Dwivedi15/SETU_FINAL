"""
Email OTP authentication endpoints.

Replaces the mobile app's demo-only client-side OTP (setu_app's
login_screen.dart generated the code locally and displayed it on screen
-- honest about being a demo, but not usable as real verification).

DEMO MODE: no email or SMS is sent. request-otp returns the code as
demo_code (see the endpoint docstring).

SCOPE -- READ BEFORE BUILDING ON THIS: verifying an OTP does NOT issue a
session token or JWT, and these endpoints do not gate anything else in
the API. SETU's real identity primitive is the device's Ed25519 keypair
(sender_id IS the hex-encoded public key), and that remains the sole
cryptographic basis for anything security-relevant in the mesh path --
see responder_service.is_authorized_responder(). Email verification
confirms that a human controls a contactable address at registration
time. It is not a parallel auth system and must not become one without a
deliberate team decision.

These routes are intentionally PUBLIC (no X-API-Key): they're called by
ordinary users' mobile apps at first-run, before any responder identity
exists. They expose no incident, profile, or responder data.
"""
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.db.base import get_db
from app.schemas.auth import OtpRequestIn, OtpRequestOut, OtpVerifyIn, OtpVerifyOut
from app.services.otp_service import (
    OTP_EXPIRY_MINUTES,
    MAX_OTP_ATTEMPTS,
    OtpCooldownError,
    request_otp,
    verify_otp,
)

router = APIRouter()

VERIFY_FAILURE_DETAIL = {
    "no_active_code": "No active verification code for this email. Request a new one.",
    "expired": "That code has expired. Request a new one.",
    "too_many_attempts": (
        f"Too many incorrect attempts (limit {MAX_OTP_ATTEMPTS}). "
        "Request a new code to continue."
    ),
    "incorrect": "That code is incorrect.",
}


@router.post("/auth/request-otp", response_model=OtpRequestOut)
def request_email_otp(payload: OtpRequestIn, db: Session = Depends(get_db)):
    """
    DEMO MODE: generates a 6-digit code, stores only its hash, and returns
    the code in the response as demo_code. No email is sent -- this server
    has no email provider. The response is explicitly marked demo_mode=True
    and delivered=False so no client can mistake it for real delivery.

    Requests inside the resend cooldown get 429 (the earlier code's
    plaintext is not recoverable), which also stops rapid re-issuing.
    """
    try:
        otp, demo_code = request_otp(db, email=payload.email, sender_id=payload.sender_id)
    except OtpCooldownError as exc:
        raise HTTPException(
            status_code=429,
            detail=f"A code was just issued. Try again in {exc.retry_after_seconds}s.",
            headers={"Retry-After": str(exc.retry_after_seconds)},
        )

    return OtpRequestOut(
        email=otp.email,
        delivered=False,
        demo_mode=True,
        expires_in_minutes=OTP_EXPIRY_MINUTES,
        detail="DEMO MODE: no email was sent. Use the demo OTP shown on screen.",
        demo_code=demo_code,
    )


@router.post("/auth/verify-otp", response_model=OtpVerifyOut)
def verify_email_otp(payload: OtpVerifyIn, db: Session = Depends(get_db)):
    """
    Verifies a submitted code. Single-use: a correct code is consumed and
    will not verify a second time.

    Returns 400 on any failure with a specific reason, so the app can
    show the user something useful ("expired" vs "incorrect" vs "request
    a new code") rather than one generic error.
    """
    ok, reason, otp = verify_otp(db, email=payload.email, code=payload.code)

    if not ok:
        raise HTTPException(
            status_code=400,
            detail=VERIFY_FAILURE_DETAIL.get(reason, "Verification failed."),
        )

    return OtpVerifyOut(
        email=otp.email,
        verified=True,
        sender_id=otp.sender_id,
        detail="Email verified successfully.",
    )
