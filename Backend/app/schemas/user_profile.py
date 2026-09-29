"""
User profile schemas.

RegisterIn is what the mobile app sends once, at first-time registration
(over normal internet, never over mesh). This is intentionally separate
from PacketIn -- profile data must never travel through /ingest or any
mesh-facing path.
"""

from typing import List, Optional

from pydantic import BaseModel, Field, ConfigDict, field_validator


class RegisterIn(BaseModel):
    sender_id: str = Field(..., max_length=256, min_length=1)
    name: str = Field(..., max_length=200)
    age: Optional[int] = Field(None, ge=0, le=150)
    gender: Optional[str] = None
    medical_history: Optional[str] = Field(None, max_length=2000)
    emergency_contacts: List[str] = Field(default_factory=list, max_length=5)

    @field_validator('emergency_contacts')
    @classmethod
    def validate_contacts(cls, v: List[str]) -> List[str]:
        for contact in v:
            if len(contact) > 32:
                raise ValueError("Contact entry too long")
        return v


class RegisterOut(BaseModel):
    id: int
    sender_id: str
    name: str

    model_config = ConfigDict(from_attributes=True)
