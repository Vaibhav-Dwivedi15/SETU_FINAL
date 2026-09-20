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

KNOWN GAP, NOT FIXED THIS PASS -- FLAGGED, NOT SILENTLY LEFT (see
docs/SECURITY_THREAT_MODEL.md / SECURITY_SCORECARD.md for the full
writeup): POST /register has NO proof-of-possession check on
sender_id. Since sender_id IS a device's Ed25519 public key (see the
mesh identity model) and public keys travel in the clear in every mesh
packet (trivially observable, per Threat Model T2), anyone who knows a
target's sender_id can currently overwrite that person's name, age,
gender, medical_history, and emergency_contacts by POSTing here --
there is no signature proving the caller actually holds the matching
private key. A real fix (requiring the request to be signed, verified
via the same signature_service.py already used for mesh packets) is
architecturally sound and this endpoint doesn't have /ingest's
must-work-offline constraint, since registration is explicitly an
online-only, internet-required step (see this file's own docstring
above and register.py's). But it DOES require a matching change to
setu_app's ProfileSyncService to actually sign its registration
payload, which this backend-only pass cannot safely ship without
coordinated testing against the real client -- an untested breaking
change to a working registration flow is worse than a documented gap.
Flagged as the second-highest-priority follow-up after the AI-dedup
finding (T7).
"""

from typing import List, Optional

from pydantic import BaseModel, Field, field_validator, ConfigDict


class RegisterIn(BaseModel):
    # 256 chars: same headroom used for sender_id everywhere else in
    # this backend this sprint (see PacketIn) -- generous over a
    # 64-hex-char Ed25519 public key without hardcoding an exact length.
    sender_id: str = Field(..., min_length=1, max_length=256)
    name: str = Field(..., min_length=1, max_length=200)
    age: Optional[int] = Field(None, ge=0, le=150)
    gender: Optional[str] = Field(None, max_length=50)
    # Free-text medical notes -- bounded generously (well beyond any
    # real use) to stop this becoming unbounded storage, not to
    # constrain legitimate medical detail.
    medical_history: Optional[str] = Field(None, max_length=2000)
    emergency_contacts: List[str] = Field(default_factory=list, max_length=5)

    @field_validator("emergency_contacts")
    @classmethod
    def _bound_contact_entries(cls, value: List[str]) -> List[str]:
        for contact in value:
            if len(contact) > 32:
                raise ValueError("emergency_contacts entry exceeds 32 characters")
        return value


class RegisterOut(BaseModel):
    id: int
    sender_id: str
    name: str

    model_config = ConfigDict(from_attributes=True)
