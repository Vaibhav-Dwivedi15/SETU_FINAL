"""
Database model for the trusted responder registry.

Closes the "termination authorization" gap flagged in the project
handoff (Section 3/6). Two layers now check a termination:
  1. This backend, via responder_service.is_authorized_responder() at
     /ingest time.
  2. Vaibhav's mesh layer, client-side, via GET /responders/keys (see
     app/routers/responders.py) -- verifies the TerminationPacket's
     signature was actually produced by a trusted key, BEFORE the
     packet is even relayed.

CONFIRMED with Vaibhav (Mesh Lead), after a flagged ambiguity:
authorization is based on the packet's sender_id -- the value
cryptographically proven by its signature -- NOT the packet's
responder_id field. responder_id is purely informational/display
metadata (e.g. a badge number shown on the dashboard); anyone can put
any string into it, so it's never checked for auth, here or mesh-side.
That's why this table's column is named public_key, not responder_id --
it holds the same Ed25519 public key value a responder's device uses as
its own sender_id when it signs a termination packet.

FIRST PASS -- confirm the registration/provisioning flow with Shaurya
(Security lead) before relying on this for anything beyond internal
testing. This is a simple allow-list; it does not implement PKI, Sybil
resistance, or any of the other roadmap-only security items.
"""

from sqlalchemy import Column, String, Integer, Boolean, DateTime
from sqlalchemy.sql import func

from app.db.base import Base


class ResponderProfile(Base):
    __tablename__ = "responder_profiles"

    id = Column(Integer, primary_key=True, index=True)

    # The responder's Ed25519 public key (hex) -- the SAME value their
    # device uses as sender_id when signing packets. This is what
    # authorization is actually checked against (see
    # responder_service.is_authorized_responder), not any packet-level
    # responder_id field, which is separate and purely cosmetic.
    public_key = Column(String, unique=True, index=True, nullable=False)

    name = Column(String, nullable=False)
    organization = Column(String, nullable=True)  # e.g. "NDRF", "Delhi Police"

    # Lets an admin revoke a responder without deleting their history --
    # incidents they already closed stay closed and auditable. Also
    # controls mesh-side trust: GET /responders/keys only returns
    # active=True keys, so revoking here removes trust on the mesh's
    # next 5-minute sync.
    is_active = Column(Boolean, default=True, nullable=False)

    created_at = Column(DateTime(timezone=True), server_default=func.now())