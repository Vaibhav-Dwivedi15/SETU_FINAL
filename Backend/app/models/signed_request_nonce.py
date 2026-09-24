"""Replay guard for signed requests (registration, voice, nearby alerts, respond)."""

from sqlalchemy import Column, DateTime, Integer, String, UniqueConstraint
from sqlalchemy.sql import func

from app.db.base import Base


class SignedRequestNonce(Base):
    """
    One row per accepted signed request. UNIQUE(sender_id, nonce): the same
    (key, nonce) can never authenticate twice, so a captured request cannot
    be replayed inside the timestamp window. Rows are pruned once older than
    twice that window (a replay would be rejected by the timestamp check by then).
    """
    __tablename__ = "signed_request_nonces"
    __table_args__ = (UniqueConstraint("sender_id", "nonce", name="uq_signed_request_sender_nonce"),)

    id = Column(Integer, primary_key=True)
    sender_id = Column(String(64), nullable=False)
    nonce = Column(String(128), nullable=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now(), index=True)
