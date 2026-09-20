"""
Government notification adapter -- Phase 2.

PURPOSE / HONEST SCOPE (read before demoing or writing this into any
judge-facing doc): No real government API (112/ERSS, state/district
emergency systems, etc.) is integrated or authorized for SETU as of this
writing. This module exists to let the full pipeline --
A -> B -> C -> D (mesh relay) -> Backend -> Government Adapter -- be
demonstrated end-to-end, with a MOCK adapter standing in for the real
one. Do not claim a real government integration exists; claim the
architecture is ready for one to be plugged in without a rewrite, which
is true and is the actual point of this design.

DESIGN: GovernmentNotificationAdapter is an abstract interface. Any
future real adapter (e.g. a genuine ERSS-112 integration) implements the
same `notify(incident) -> GovernmentNotificationResult` contract and can
be swapped in via get_active_adapter() below -- nothing in
incident_service.py or elsewhere needs to change.

NON-BLOCKING, mirrors the AI-analysis pattern used elsewhere in this
codebase (see ai_analysis_service.py): a government notification
failure (mock or real) must NEVER break incident ingestion. notify_government()
swallows all adapter exceptions itself and always returns normally.

WHEN THIS FIRES: called from incident_service.handle_sos_packet, only
for genuinely NEW incidents (same condition as the SMS notification),
never on a merge -- see handle_sos_packet's docstring for why merges
don't re-notify.
"""

import uuid
import logging
from abc import ABC, abstractmethod
from dataclasses import dataclass
from typing import Optional

from sqlalchemy.orm import Session

from app.models.government_notification import GovernmentNotificationLog, GovernmentNotificationStatus
from app.models.incident import Incident

logger = logging.getLogger("setu.government_notification")


@dataclass
class GovernmentNotificationResult:
    success: bool
    reference_id: Optional[str]
    detail: str


class GovernmentNotificationAdapter(ABC):
    """
    Contract every government notification adapter must implement --
    mock today, real (ERSS-112 / state systems) later. Swapping the
    active adapter (see get_active_adapter()) is the only change needed
    anywhere in the codebase when a real integration is authorized.
    """

    name: str

    @abstractmethod
    def notify(self, incident: Incident) -> GovernmentNotificationResult:
        ...


class MockGovernmentAdapter(GovernmentNotificationAdapter):
    """
    Simulates a government notification call so the full pipeline can be
    demoed safely with no real external dependency. Always "succeeds"
    (this is a demo stand-in, not a reliability test) and returns an
    obviously-fake reference id -- MOCK-GOV-<uuid> -- so it can never be
    mistaken for a real government tracking number in a screenshot, log,
    or dashboard.
    """

    name = "mock"

    def notify(self, incident: Incident) -> GovernmentNotificationResult:
        reference_id = f"MOCK-GOV-{uuid.uuid4().hex[:12]}"
        logger.info(
            "MockGovernmentAdapter: simulated notify for incident_id=%s "
            "type=%s lat=%s lon=%s -> reference_id=%s",
            incident.id, incident.incident_type,
            incident.latitude, incident.longitude, reference_id,
        )
        return GovernmentNotificationResult(
            success=True,
            reference_id=reference_id,
            detail="Simulated government notification (mock adapter, no real API call made)",
        )


def get_active_adapter() -> GovernmentNotificationAdapter:
    """
    Single place that decides which adapter is live. Today this always
    returns the mock. When a real adapter is built and authorized, this
    is the only line that changes to switch it on -- incident_service.py
    and the rest of the codebase stay untouched.
    """
    return MockGovernmentAdapter()


def notify_government(db: Session, incident: Incident) -> None:
    """
    Fire-and-log call to the active government notification adapter.
    Never raises -- any adapter exception is caught, logged, and written
    to GovernmentNotificationLog as a FAILED row instead of propagating,
    so a government-adapter problem can never break incident ingestion
    (same non-blocking guarantee AI analysis and SMS notification give).

    Uses its own commit, isolated from the caller's transaction -- by
    the time this runs, the incident itself is already committed (see
    handle_sos_packet: this is called after commit/lock-release), so a
    log-write failure here can never roll back real incident data.
    """
    adapter = get_active_adapter()
    request_payload = {
        "incident_id": incident.id,
        "incident_type": incident.incident_type,
        "latitude": incident.latitude,
        "longitude": incident.longitude,
        "sender_priority": incident.sender_priority,
        "ai_priority": incident.ai_priority,
    }

    try:
        result = adapter.notify(incident)
        log_entry = GovernmentNotificationLog(
            incident_id=incident.id,
            adapter_name=adapter.name,
            status=GovernmentNotificationStatus.SENT if result.success else GovernmentNotificationStatus.FAILED,
            reference_id=result.reference_id,
            request_payload=request_payload,
            response_detail=result.detail,
        )
        db.add(log_entry)
        db.commit()
    except Exception as e:
        logger.exception("Government notification adapter '%s' raised for incident_id=%s", adapter.name, incident.id)
        db.rollback()
        try:
            log_entry = GovernmentNotificationLog(
                incident_id=incident.id,
                adapter_name=adapter.name,
                status=GovernmentNotificationStatus.FAILED,
                reference_id=None,
                request_payload=request_payload,
                response_detail=f"Adapter raised an exception: {e}",
            )
            db.add(log_entry)
            db.commit()
        except Exception:
            # Even the failure-log write failed (e.g. DB connection down).
            # Nothing more to do -- this must never propagate up into
            # ingest_packets() and break the request.
            logger.exception("Failed to write government notification failure log for incident_id=%s", incident.id)
            db.rollback()
