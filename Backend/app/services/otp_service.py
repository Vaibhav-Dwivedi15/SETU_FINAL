"""
Email OTP generation and verification.

See app/models/email_otp.py for the security reasoning behind hashing,
attempt caps, and single-use consumption. This module holds the actual
policy constants and the two operations the auth router exposes.

RATE LIMITING: requesting a new code for an address that already has a
live un-consumed code within RESEND_COOLDOWN_SECONDS returns the
existing record rather than generating and emailing a new one. Without
this, anyone could use the endpoint to mail-bomb an arbitrary address.
This is deliberately a simple per-address DB check, not a full rate
limiter -- it is adequate for this project's scale and honest about
being that rather than pretending to be a hardened service.

TIMING: verification uses hmac.compare_digest rather than `==` so a
correct-prefix code can't be distinguished by response timing.
"""
import hashlib
import hmac
import logging
import secrets
from datetime import datetime, timedelta, timezone
from typing import Optional, Tuple

from sqlalchemy.orm import Session

from app.core.config import settings
from app.models.email_otp import EmailOtp
from app.services.email_service import send_otp_email, smtp_is_configured

logger = logging.getLogger("setu.otp")

OTP_LENGTH = 6
OTP_EXPIRY_MINUTES = 10
MAX_OTP_ATTEMPTS = 5
RESEND_COOLDOWN_SECONDS = 60


def _hash_code(code: str) -> str:
    return hashlib.sha256(code.encode("utf-8")).hexdigest()


def _generate_code() -> str:
    """
    Cryptographically-random 6-digit code. secrets, not random --
    random's Mersenne Twister is predictable from prior outputs and has
    no business generating anything authentication-related.
    """
    return "".join(secrets.choice("0123456789") for _ in range(OTP_LENGTH))


def _now() -> datetime:
    return datetime.now(timezone.utc)


def _as_aware(value: Optional[datetime]) -> Optional[datetime]:
    """
    SQLite (used by the test suite) returns naive datetimes even for
    timezone-aware columns, while Postgres returns aware ones. Comparing
    the two raises TypeError. Normalizes to UTC-aware so expiry checks
    behave identically on both.
    """
    if value is None:
        return None
    if value.tzinfo is None:
        return value.replace(tzinfo=timezone.utc)
    return value


def demo_otp_active() -> bool:
    """
    True only when SMTP is unavailable AND the project's existing
    development switch (settings.debug -- the same gate security.py uses
    for the dev responder key) is on. Never true in production (DEBUG
    unset/false) and never true when real email delivery is possible, so
    a working SMTP setup always takes the real path.
    """
    return bool(settings.debug) and not smtp_is_configured()


def request_otp(
    db: Session, email: str, sender_id: Optional[str] = None
) -> Tuple[EmailOtp, bool, bool, Optional[str]]:
    """
    Creates (or reuses, within the cooldown) an OTP for this email and
    attempts delivery.

    Returns (otp_row, was_newly_created, delivered, demo_code).

    demo_code is non-None ONLY in development/demo mode (see
    demo_otp_active). It is the same random one-time code that was
    hashed and stored -- verification stays real (hashed, expiring,
    single-use, attempt-capped); the code is just handed back instead of
    emailed, mirroring the original demo where the code was shown
    on-screen. delivered stays False: no email was sent, and we never
    claim otherwise.

    delivered is the honest result of the SMTP attempt -- False means the
    code exists in the database but no email actually went out. The
    caller must surface that rather than reporting success.
    """
    email = email.strip().lower()
    now = _now()

    # Reuse a still-valid recent code instead of spamming the address.
    existing = (
        db.query(EmailOtp)
        .filter(
            EmailOtp.email == email,
            EmailOtp.consumed_at.is_(None),
        )
        .order_by(EmailOtp.created_at.desc())
        .first()
    )

    demo = demo_otp_active()

    # Demo mode skips the resend-reuse shortcut: a reused row only holds
    # a hash, so its plaintext couldn't be shown again. There is no
    # mail-bombing risk since nothing is emailed.
    if existing and not demo:
        created_at = _as_aware(existing.created_at) or now
        expires_at = _as_aware(existing.expires_at)
        within_cooldown = (now - created_at).total_seconds() < RESEND_COOLDOWN_SECONDS
        still_valid = expires_at is not None and expires_at > now

        if within_cooldown and still_valid:
            logger.info("OTP resend suppressed for %s (within %ss cooldown)", email, RESEND_COOLDOWN_SECONDS)
            return existing, False, existing.delivered, None

    if demo and existing:
        # Supersede older live codes so only the freshly shown one works.
        db.query(EmailOtp).filter(
            EmailOtp.email == email, EmailOtp.consumed_at.is_(None)
        ).update({EmailOtp.consumed_at: now}, synchronize_session=False)

    code = _generate_code()
    otp = EmailOtp(
        email=email,
        code_hash=_hash_code(code),
        sender_id=sender_id,
        expires_at=now + timedelta(minutes=OTP_EXPIRY_MINUTES),
        attempts=0,
        delivered=False,
    )
    db.add(otp)
    db.commit()
    db.refresh(otp)

    if demo:
        logger.warning(
            "DEMO OTP mode: SMTP unavailable and DEBUG is on -- returning the code "
            "in the API response for %s instead of emailing it", email
        )
        return otp, True, False, code

    delivered = send_otp_email(email, code, OTP_EXPIRY_MINUTES)
    if delivered:
        otp.delivered = True
        db.commit()
        db.refresh(otp)

    return otp, True, delivered, None


def verify_otp(db: Session, email: str, code: str) -> Tuple[bool, str, Optional[EmailOtp]]:
    """
    Verifies a submitted code.

    Returns (ok, reason, otp_row). reason is a short machine-readable
    string the router maps to a message: "verified", "no_active_code",
    "expired", "too_many_attempts", "incorrect".

    A wrong attempt increments attempts and is committed immediately, so
    the cap holds even across separate requests.
    """
    email = email.strip().lower()
    now = _now()

    otp = (
        db.query(EmailOtp)
        .filter(
            EmailOtp.email == email,
            EmailOtp.consumed_at.is_(None),
        )
        .order_by(EmailOtp.created_at.desc())
        .first()
    )

    if not otp:
        return False, "no_active_code", None

    expires_at = _as_aware(otp.expires_at)
    if expires_at is not None and expires_at <= now:
        return False, "expired", otp

    if otp.attempts >= MAX_OTP_ATTEMPTS:
        return False, "too_many_attempts", otp

    if not hmac.compare_digest(otp.code_hash, _hash_code(code.strip())):
        otp.attempts += 1
        db.commit()
        return False, "incorrect", otp

    otp.consumed_at = now
    db.commit()
    db.refresh(otp)
    return True, "verified", otp


def otp_delivery_available() -> bool:
    """Exposed so the router can tell a client up front that SMTP isn't set up."""
    return smtp_is_configured()
