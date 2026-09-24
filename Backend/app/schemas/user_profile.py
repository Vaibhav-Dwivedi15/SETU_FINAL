"""
User profile schemas.

RegisterIn is what the mobile app sends once, at first-time registration
(over normal internet, never over mesh). This is intentionally separate
from PacketIn -- profile data must never travel through /ingest or any
mesh-facing path.

SEP 2026 SECURITY HARDENING: every field below now has an explicit
bound, for the same reason PacketIn's fields were bounded this sprint
(see app/schemas/packet.py) -- this endpoint was effectively unbounded
free-text storage before. Real values from setu_app's ProfileSyncService
are all far inside these limits; only what a genuine client could never
send is rejected.

PROOF OF POSSESSION (Block 2): POST /register now requires a request signature
from the Ed25519 key that IS sender_id -- see routers/register.py and
services/request_auth.py. (This replaces the "known gap" that used to be
described here.)
"""

import re
from typing import List, Optional

from pydantic import BaseModel, Field, field_validator, ConfigDict


class RegisterIn(BaseModel):
    # 256 chars: same headroom used for sender_id everywhere else in
    # this backend this sprint (see PacketIn) -- generous over a
    # 64-hex-char Ed25519 public key without hardcoding an exact length.
    sender_id: str = Field(..., min_length=1, max_length=256)
    name: str = Field(..., min_length=1, max_length=200)  # whitespace-only rejected below
    age: Optional[int] = Field(None, ge=0, le=150)
    gender: Optional[str] = Field(None, max_length=50)
    # Free-text medical notes -- bounded generously (well beyond any
    # real use) to stop this becoming unbounded storage, not to
    # constrain legitimate medical detail.
    medical_history: Optional[str] = Field(None, max_length=2000)
    emergency_contacts: List[str] = Field(default_factory=list, max_length=5)

    @field_validator("name")
    @classmethod
    def _name_not_blank(cls, value: str) -> str:
        if not value.strip():
            raise ValueError("name must not be blank")
        return value.strip()

    @field_validator("emergency_contacts")
    @classmethod
    def _bound_contact_entries(cls, value: List[str]) -> List[str]:
        for contact in value:
            if len(contact) > 32:
                raise ValueError("emergency_contacts entry exceeds 32 characters")
            # Block 2: must look like a phone number (7-15 digits, optional leading +,
            # spaces/dashes/parentheses allowed). Generous on purpose: it only rejects
            # values that cannot be dialled, and stops free text reaching the SMS gateway.
            compact = re.sub(r"[\s\-().]", "", contact)
            if not re.fullmatch(r"\+?\d{7,15}", compact):
                raise ValueError("emergency_contacts entry is not a valid phone number")
        return value


class RegisterOut(BaseModel):
    id: int
    sender_id: str
    name: str

    model_config = ConfigDict(from_attributes=True)
