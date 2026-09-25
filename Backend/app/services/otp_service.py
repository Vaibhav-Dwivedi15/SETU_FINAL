"""
Email OTP generation and verification (DEMO mode: nothing is emailed).

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

from app.models.email_otp import EmailOtp

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


class OtpCooldownError(Exception):
    """A live code was issued less than RESEND_COOLDOWN_SECONDS ago."""

    def __init__(self, retry_after_seconds: int):
        super().__init__(f"retry after {retry_after_seconds}s")
        self.retry_after_seconds = retry_after_seconds


def request_otp(db: Session, email: str, sender_id: Optional[str] = None) -> Tuple[EmailOtp, str]:
    """
    Creates an OTP for this email and returns (otp_row, demo_code).

    DEMO-ONLY: no email is sent and no email provider exists in this
    project. The code is returned to the caller so the app can display
    it. Only the hash is stored; expiry, single use and the attempt cap
    are enforced exactly as before in verify_otp.

    Raises OtpCooldownError if a live, unconsumed code for this address
    was issued within RESEND_COOLDOWN_SECONDS. The plaintext of that code
    is not recoverable (hash only), so the caller must wait it out.
    """
    email = email.strip().lower()
    now = _now()

    existing = (
        db.query(EmailOtp)
        .filter(
            EmailOtp.email == email,
            EmailOtp.consumed_at.is_(None),
        )
        .order_by(EmailOtp.created_at.desc())
        .first()
    )

    if existing:
        created_at = _as_aware(existing.created_at) or now
        expires_at = _as_aware(existing.expires_at)
        elapsed = (now - created_at).total_seconds()
        if elapsed < RESEND_COOLDOWN_SECONDS and expires_at is not None and expires_at > now:
            wait = max(1, int(RESEND_COOLDOWN_SECONDS - elapsed))
            logger.info("OTP resend blocked for %s (cooldown, %ss left)", email, wait)
            raise OtpCooldownError(wait)

        # Supersede older live codes so only the freshly issued one works.
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

    logger.warning("DEMO OTP issued for %s (no email is sent by this server)", email)
    return otp, code


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
