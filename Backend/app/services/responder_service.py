"""
Responder authorization service.

Checks a TerminationPacket's SENDER against the trusted responder
registry (ResponderProfile) before a termination is allowed to close an
incident.

CONFIRMED with Vaibhav, Mesh Lead: authorization is based on
packet.sender_id -- the value cryptographically proven by the packet's
signature -- NOT packet.responder_id. responder_id is purely
informational/display metadata (e.g. a badge number); anyone can put any
string into it, so it's never used for auth, here or mesh-side. Mesh's
own checkResponder() (termination_packet.dart) checks sender_id for the
same reason.

FIRST PASS -- simple allow-list only. Real cryptographic proof that
sender_id wasn't spoofed still depends on signature_service.py, which is
a stub pending the Mesh team's signing scheme.
"""

from typing import Optional

from sqlalchemy.orm import Session

from app.models.responder import ResponderProfile


def is_authorized_responder(db: Session, sender_id: Optional[str]) -> bool:
    """
    True if sender_id (the packet's cryptographic sender identity) is a
    registered, active responder public key.
    """
    if not sender_id:
        return False

    responder = (
        db.query(ResponderProfile)
        .filter(ResponderProfile.public_key == sender_id)
        .first()
    )
    return responder is not None and responder.is_active