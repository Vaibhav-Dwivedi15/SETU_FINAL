"""
Validation logic for incoming packets, run before storage.

Two checks live here for now:
- TTL expiry: has this packet been in transit too long to still be actionable?
- Duplicate detection: has this exact packet_id already been stored?
  (Not the same as incident-level deduplication -- that's the dedup
  service that merges DIFFERENT packet_ids reporting the same event.
  This is a simpler check: rejecting the identical packet_id twice, e.g.
  from a relay loop or retried sync.)

Signature verification is intentionally NOT here -- it lives in
signature_service.py, since it needs a real key/verification scheme
agreed with the Mesh team (whether it's a shared secret, per-device
keypair, etc.). Until that's decided, it's a stub that always passes.

NOTE: packet.timestamp is an ISO 8601 string (frozen mesh spec), not a
Unix epoch int -- this changed when the schema was aligned to Vaibhav's
mesh packet format. is_ttl_expired parses it accordingly.
"""

from datetime import datetime, timezone

from sqlalchemy.orm import Session

from app.core.config import settings
from app.models.packet import RawPacket
from app.schemas.packet import PacketIn


def is_ttl_expired(packet: PacketIn, max_age_seconds: int | None = None) -> bool:
    """A packet older than max_age_seconds (default: settings.packet_max_age_seconds) is stale."""
    if max_age_seconds is None:
        max_age_seconds = settings.packet_max_age_seconds
    try:
        sent_at = datetime.fromisoformat(packet.timestamp.replace("Z", "+00:00"))
    except ValueError:
        # Unparseable timestamp -- treat as expired rather than crash
        # /ingest on a malformed packet.
        return True

    if sent_at.tzinfo is None:
        sent_at = sent_at.replace(tzinfo=timezone.utc)

    age = (datetime.now(timezone.utc) - sent_at).total_seconds()
    return age > max_age_seconds


def is_duplicate(db: Session, packet: PacketIn) -> bool:
    """
    True if this exact packet_id has already been stored. Rejected packets
    are persisted under a namespaced id (see ingest._rejected_packet_id), so
    an unsigned forgery can never occupy a genuine packet's id.
    """
    existing = (
        db.query(RawPacket)
        .filter(RawPacket.packet_id == packet.packet_id)
        .first()
    )
    return existing is not None