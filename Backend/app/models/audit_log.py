"""
Incident audit log.

Records every mutation to an Incident -- created, merged (a
corroborating packet attached), or closed -- so the dashboard can show
a timeline and so the project can honestly claim an audit trail exists
(per project memory: "every incident modification should be audited").

This is intentionally append-only: rows are never updated or deleted,
only inserted, mirroring the same "raw evidence, never overwritten"
philosophy already used for RawPacket.
"""

import enum

from sqlalchemy import Column, Integer, String, DateTime, ForeignKey, Enum as SAEnum
from sqlalchemy.sql import func

from app.db.base import Base


class AuditAction(str, enum.Enum):
    CREATED = "CREATED"
    MERGED = "MERGED"
    CLOSED = "CLOSED"


class IncidentAuditLog(Base):
    __tablename__ = "incident_audit_log"

    id = Column(Integer, primary_key=True, index=True)
    incident_id = Column(Integer, ForeignKey("incidents.id"), nullable=False, index=True)
    action = Column(SAEnum(AuditAction), nullable=False)
    packet_id = Column(String, nullable=True)  # the packet that triggered this action
    detail = Column(String, nullable=True)      # short human-readable note, optional
    created_at = Column(DateTime(timezone=True), server_default=func.now())