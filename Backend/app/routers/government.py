"""
Government notification log endpoints.

Completes Phase 2 by making the government notification adapter's audit
trail visible. The adapter itself (app/services/government_notification_service.py)
has been firing and writing GovernmentNotificationLog rows since Phase 2,
but nothing could read them back -- so from the dashboard's point of
view that whole step of the pipeline was invisible.

HONESTY -- NON-NEGOTIABLE ON THIS ONE: the active adapter is a MOCK. No
real 112/ERSS or state emergency API is integrated or authorized. Every
response from these endpoints carries adapter_name and an is_mock flag,
and the reference ids are deliberately prefixed MOCK-GOV- so they can
never be mistaken for real government tracking numbers in a screenshot
or demo. Do not strip those markers to make a demo look better.

Responder-API-key gated, like every other dashboard-facing route.
"""
from typing import List

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.core.security import verify_responder_api_key
from app.db.base import get_db
from app.models.government_notification import GovernmentNotificationLog
from app.models.incident import Incident
from app.schemas.government import GovernmentNotificationOut, GovernmentAdapterStatusOut
from app.services.government_notification_service import get_active_adapter, MockGovernmentAdapter

router = APIRouter()


def _to_out(row: GovernmentNotificationLog) -> GovernmentNotificationOut:
    return GovernmentNotificationOut(
        id=row.id,
        incident_id=row.incident_id,
        adapter_name=row.adapter_name,
        # Explicit rather than inferred from the name string, so this
        # stays correct if a real adapter is ever added alongside the mock.
        is_mock=row.adapter_name == MockGovernmentAdapter.name,
        status=row.status,
        reference_id=row.reference_id,
        request_payload=row.request_payload,
        response_detail=row.response_detail,
        created_at=row.created_at,
    )


@router.get("/incidents/{incident_id}/government-notifications", response_model=List[GovernmentNotificationOut])
def get_incident_government_notifications(
    incident_id: int,
    db: Session = Depends(get_db),
    _: None = Depends(verify_responder_api_key),
):
    """
    Every government-notification attempt recorded for this incident,
    newest first. Append-only, so a retry shows as an additional row
    rather than overwriting history.
    """
    incident = db.query(Incident).filter(Incident.id == incident_id).first()
    if not incident:
        raise HTTPException(status_code=404, detail="Incident not found.")

    rows = (
        db.query(GovernmentNotificationLog)
        .filter(GovernmentNotificationLog.incident_id == incident_id)
        .order_by(GovernmentNotificationLog.created_at.desc())
        .all()
    )
    return [_to_out(r) for r in rows]


@router.get("/government/notifications", response_model=List[GovernmentNotificationOut])
def list_government_notifications(
    limit: int = 100,
    db: Session = Depends(get_db),
    _: None = Depends(verify_responder_api_key),
):
    """
    Full recent log across all incidents -- the dashboard's
    "has the government pipeline actually been firing?" view.
    """
    limit = max(1, min(limit, 500))
    rows = (
        db.query(GovernmentNotificationLog)
        .order_by(GovernmentNotificationLog.created_at.desc())
        .limit(limit)
        .all()
    )
    return [_to_out(r) for r in rows]


@router.get("/government/adapter-status", response_model=GovernmentAdapterStatusOut)
def government_adapter_status(
    db: Session = Depends(get_db),
    _: None = Depends(verify_responder_api_key),
):
    """
    Which adapter is live, and whether it's the mock. The dashboard uses
    this to render an unmissable "simulated" banner -- so nobody looking
    at the screen can mistake a mock dispatch for a real one.
    """
    adapter = get_active_adapter()
    total = db.query(GovernmentNotificationLog).count()

    return GovernmentAdapterStatusOut(
        adapter_name=adapter.name,
        is_mock=isinstance(adapter, MockGovernmentAdapter),
        total_notifications=total,
        detail=(
            "Mock adapter active. No real 112/ERSS or state emergency API is integrated "
            "or authorized. Reference IDs prefixed MOCK-GOV- are simulated and are not "
            "real government tracking numbers."
            if isinstance(adapter, MockGovernmentAdapter)
            else f"Live adapter '{adapter.name}' active."
        ),
    )
