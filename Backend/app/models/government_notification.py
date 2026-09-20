"""
Database model for government notification audit log.

Phase 2: every time an incident triggers a call to the government
notification adapter (real or mock), one row is written here -- success
or failure. This is the audit trail proving the A -> B -> C -> D ->
Backend -> Government Adapter flow actually fired for a given incident,
which matters for demoing this end-to-end without overclaiming (no real
government API is authorized/integrated yet -- see
app/services/government_notification_service.py's module docstring).

One incident can have multiple rows here (e.g. a retry, or a genuine
resend) -- this table is an append-only log, not a 1:1 status field on
Incident, so history is never overwritten.
"""
import enum
from sqlalchemy import Column, Integer, String, DateTime, Enum as SAEnum, JSON, ForeignKey
from sqlalchemy.sql import func
from app.db.base import Base


class GovernmentNotificationStatus(str, enum.Enum):
    SENT = "SENT"
    FAILED = "FAILED"


class GovernmentNotificationLog(Base):
    __tablename__ = "government_notification_logs"

    id = Column(Integer, primary_key=True, index=True)
    incident_id = Column(Integer, ForeignKey("incidents.id"), nullable=False, index=True)

    # Which adapter handled this call -- "mock" today, will be a real
    # adapter name (e.g. "erss_112") once a real government API is
    # authorized and integrated. Never hardcode this assumption anywhere
    # else -- always read it from here for judge-facing/audit purposes.
    adapter_name = Column(String, nullable=False)

    status = Column(SAEnum(GovernmentNotificationStatus), nullable=False)

    # Adapter-returned reference/tracking id. For MockGovernmentAdapter
    # this is a clearly-fake id (see service docstring) -- NEVER presented
    # as if it were a real government tracking number.
    reference_id = Column(String, nullable=True)

    # What was actually sent to the adapter, for audit/debugging.
    request_payload = Column(JSON, nullable=True)

    # Human-readable outcome detail (success message, or exception text
    # on failure -- adapter calls never raise past this point, see
    # government_notification_service.py).
    response_detail = Column(String, nullable=True)

    created_at = Column(DateTime(timezone=True), server_default=func.now())
