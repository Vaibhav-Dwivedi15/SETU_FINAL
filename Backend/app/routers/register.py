"""
Registration endpoint.

Collects a sender's full profile once, over normal internet, at app
install/first-run time. This is the ONLY place profile data enters the
system -- mesh packets never carry this information.
"""

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.db.base import get_db
from app.models.user_profile import UserProfile
from app.schemas.user_profile import RegisterIn, RegisterOut

router = APIRouter()


@router.post("/register", response_model=RegisterOut)
def register_user(payload: RegisterIn, db: Session = Depends(get_db)):
    existing = db.query(UserProfile).filter(
        UserProfile.sender_id == payload.sender_id
    ).first()

    if existing:
        raise HTTPException(
            status_code=409,
            detail=f"sender_id '{payload.sender_id}' is already registered.",
        )

    profile = UserProfile(
        sender_id=payload.sender_id,
        name=payload.name,
        age=payload.age,
        gender=payload.gender,
        medical_history=payload.medical_history,
        emergency_contacts=payload.emergency_contacts,
    )
    db.add(profile)
    db.commit()
    db.refresh(profile)

    return profile