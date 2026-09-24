"""
Idempotency ledger for emergency-contact SMS (Block 2).

One row per (notification event, contact). The UNIQUE constraint is the
idempotency guard: whoever inserts the row owns the send, so a retry, a
duplicate upload of the same packet, or two concurrent requests can never
send the same SMS twice. Only a SHA-256 of the normalised number is stored --
never the number or the message text.
"""

from sqlalchemy import Column, DateTime, Integer, String, UniqueConstraint
from sqlalchemy.sql import func

from app.db.base import Base


class SmsNotification(Base):
    __tablename__ = "sms_notifications"
    __table_args__ = (UniqueConstraint("event_key", "contact_hash", name="uq_sms_event_contact"),)

    id = Column(Integer, primary_key=True, index=True)
    # e.g. "incident-created:<incident_id>" -- one event per newly created incident.
    event_key = Column(String(128), nullable=False, index=True)
    contact_hash = Column(String(64), nullable=False)
    # "pending" (claimed, send in flight -- treated as sent on crash: at-most-once),
    # "queued" (gateway accepted), "failed" (gateway refused; may be retried).
    status = Column(String(16), nullable=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())
