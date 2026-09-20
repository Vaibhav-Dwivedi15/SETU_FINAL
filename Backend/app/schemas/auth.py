"""
Email OTP auth schemas.

EmailStr requires the `email-validator` package (pulled in via
pydantic[email] -- see requirements.txt). Using a plain str here instead
would let obviously-invalid addresses through to the SMTP layer and turn
a clear 422 into a confusing delivery failure.
"""
from typing import Optional

from pydantic import BaseModel, EmailStr, Field


class OtpRequestIn(BaseModel):
    email: EmailStr
    # Optional: the device's Ed25519 public key (hex), so a verified
    # email can be bound to the device identity in one step. See
    # app/models/email_otp.py on why this is a binding, not a session.
    sender_id: Optional[str] = None


class OtpRequestOut(BaseModel):
    email: EmailStr
    # Honest delivery reporting -- False means the code exists but no
    # email actually went out (SMTP unconfigured or send failed). The
    # client MUST NOT show "code sent" when this is False.
    delivered: bool
    expires_in_minutes: int
    detail: str


class OtpVerifyIn(BaseModel):
    email: EmailStr
    code: str = Field(..., min_length=4, max_length=10)


class OtpVerifyOut(BaseModel):
    email: EmailStr
    verified: bool
    sender_id: Optional[str] = None
    detail: str
