"""
Responder registry schemas.

ResponderIn/ResponderOut: provisioning trusted responders who are
allowed to send TERMINATION packets (admin/internal use, API-key gated).
public_key is the responder's Ed25519 public key (hex) -- the same value
their device uses as sender_id when signing packets. This is the value
checked at /ingest time; it has nothing to do with a packet's own
responder_id field, which is separate, packet-level, and purely
informational (see app/models/responder.py for the full explanation).

ResponderKeysOut: the public contract consumed by mesh relay devices
directly (see GET /responders/keys), confirmed with Vaibhav, Mesh Lead.
"""

from datetime import datetime
from typing import List, Optional

from pydantic import BaseModel


class ResponderIn(BaseModel):
    public_key: str
    name: str
    organization: Optional[str] = None


class ResponderOut(BaseModel):
    id: int
    public_key: str
    name: str
    organization: Optional[str] = None
    is_active: bool
    created_at: datetime

    class Config:
        from_attributes = True


class ResponderKeysOut(BaseModel):
    responder_public_keys: List[str]