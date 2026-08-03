"""
User profile schemas.

RegisterIn is what the mobile app sends once, at first-time registration
(over normal internet, never over mesh). This is intentionally separate
from PacketIn -- profile data must never travel through /ingest or any
mesh-facing path.
"""

from typing import List, Optional

from pydantic import BaseModel, Field


class RegisterIn(BaseModel):
    sender_id: str
    name: str
    age: Optional[int] = Field(None, ge=0, le=150)
    gender: Optional[str] = None
    medical_history: Optional[str] = None
    emergency_contacts: List[str] = Field(default_factory=list, max_length=5)


class RegisterOut(BaseModel):
    id: int
    sender_id: str
    name: str

    class Config:
        from_attributes = True