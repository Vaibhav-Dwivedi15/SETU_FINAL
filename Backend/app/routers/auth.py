"""
Email OTP authentication endpoints.

Replaces the mobile app's demo-only client-side OTP (setu_app's
login_screen.dart generated the code locally and displayed it on screen
-- honest about being a demo, but not usable as real verification).

WHY EMAIL, NOT SMS: see app/services/email_service.py's module docstring.
Short version: SMS OTP in India needs a paid gateway plus TRAI DLT
registration; email is free and has no telecom regulatory dependency.

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
import logging

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.db.base import get_db
from app.schemas.auth import OtpRequestIn, OtpRequestOut, OtpVerifyIn, OtpVerifyOut
from app.services.otp_service import (
    OTP_EXPIRY_MINUTES,
    MAX_OTP_ATTEMPTS,
    request_otp,
    verify_otp,
    otp_delivery_available,
)

logger = logging.getLogger("setu.auth")

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
    Generates a 6-digit code, stores it hashed, and emails it.

    Returns 200 with delivered=False rather than an error when SMTP
    isn't configured or the send fails -- the client needs to be able to
    tell the difference between "we couldn't email you" and "your
    request was malformed", and must show the former honestly instead of
    a misleading "code sent" message.

    Repeated requests for the same address inside the resend cooldown
    reuse the existing live code instead of emailing a new one, so this
    endpoint can't be used to mail-bomb an address.
    """
    otp, was_new, delivered, demo_code = request_otp(db, email=payload.email, sender_id=payload.sender_id)

    if delivered:
        detail = f"Verification code sent to {otp.email}."
    elif demo_code is not None:
        detail = "Demo mode: email delivery is unavailable, so no email was sent. Use the code shown below."
    elif not otp_delivery_available():
        # Config specifics (which SMTP vars) stay in the server log only.
        logger.error("request-otp failed: SMTP is not configured on this server")
        detail = "Could not send the verification email. Please try again later."
    else:
        detail = "Could not send the verification email. Check the address and try again."

    return OtpRequestOut(
        email=otp.email,
        delivered=delivered,
        expires_in_minutes=OTP_EXPIRY_MINUTES,
        detail=detail,
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
