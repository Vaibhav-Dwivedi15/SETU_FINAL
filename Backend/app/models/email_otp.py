"""
Email OTP model.

Replaces the mobile app's demo-only local OTP (see setu_app's
login_screen.dart, which generated a 6-digit code client-side and showed
it on screen). Email was chosen over SMS OTP deliberately: SMS OTP in
India requires a paid gateway plus TRAI DLT sender registration, neither
of which this project has. Email OTP costs nothing and has no telecom
regulatory dependency.

SECURITY NOTES (these are not decorative -- read before changing):
  - The OTP is stored HASHED (SHA-256), never in plaintext. A database
    read must not hand someone a working login code.
  - attempts is capped (MAX_OTP_ATTEMPTS in otp_service.py) so a code
    can't be brute-forced -- 6 digits is only a million combinations,
    which is nothing without a limit.
  - consumed_at makes verification single-use. A correct code that was
    already used is rejected on every subsequent attempt.
  - Rows are looked up by (email, not consumed, not expired), so old
    codes for the same address never interfere with a fresh one.

This table intentionally does NOT hold a session/JWT. Verifying an OTP
returns a sender_id binding only -- SETU's real identity primitive is
the device's Ed25519 keypair (sender_id IS the hex-encoded public key),
and that is what authorizes anything security-relevant in the mesh path.
Email verification exists to confirm a human owns a contactable address
at registration time, not to become a parallel auth system. Do not grow
this into one without a deliberate team decision.
"""
from sqlalchemy import Column, Integer, String, DateTime, Boolean
from sqlalchemy.sql import func

from app.db.base import Base


class EmailOtp(Base):
    __tablename__ = "email_otps"

    id = Column(Integer, primary_key=True, index=True)

    email = Column(String, nullable=False, index=True)

    # SHA-256 hex digest of the 6-digit code. Never the code itself.
    code_hash = Column(String, nullable=False)

    # Optional binding: which device/sender this OTP was requested for.
    # Lets the mobile app tie a verified email to its existing keypair
    # identity in one step, instead of a second round trip.
    sender_id = Column(String, nullable=True, index=True)

    expires_at = Column(DateTime(timezone=True), nullable=False)
    consumed_at = Column(DateTime(timezone=True), nullable=True)

    attempts = Column(Integer, default=0, nullable=False)

    # Always False: DEMO mode, no email is sent by this server.
    delivered = Column(Boolean, default=False, nullable=False)

    created_at = Column(DateTime(timezone=True), server_default=func.now())
