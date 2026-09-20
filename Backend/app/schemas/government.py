"""
Government notification log schemas.

is_mock is a first-class field, not an afterthought -- the dashboard
renders a visible "simulated" marker from it. See
app/routers/government.py's docstring on why that marker must not be
removed to make a demo look cleaner.
"""
from datetime import datetime
from typing import Any, Dict, Optional

from pydantic import BaseModel, ConfigDict

from app.models.government_notification import GovernmentNotificationStatus


class GovernmentNotificationOut(BaseModel):
    id: int
    incident_id: int
    adapter_name: str
    is_mock: bool
    status: GovernmentNotificationStatus
    reference_id: Optional[str] = None
    request_payload: Optional[Dict[str, Any]] = None
    response_detail: Optional[str] = None
    created_at: datetime

    model_config = ConfigDict(from_attributes=True)


class GovernmentAdapterStatusOut(BaseModel):
    adapter_name: str
    is_mock: bool
    total_notifications: int
    detail: str
