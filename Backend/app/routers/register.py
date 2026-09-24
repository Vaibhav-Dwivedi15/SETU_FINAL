"""
Registration endpoint.

Collects a sender's full profile once, over normal internet, at app
install/first-run time. This is the ONLY place profile data enters the
system -- mesh packets never carry this information.

Aug 6 2026 fix: previously raised 409 Conflict on any second call for
the same sender_id, meaning there was no way to update
emergency_contacts after initial registration -- a real gap, since
Contacts is a separate screen from Complete Your Profile, so the
common real-world sequence (register once at profile setup, THEN add
contacts afterward, or edit/remove them later) meant the backend's
copy of emergency_contacts would silently go stale forever after the
first call. Now upserts: a second call for the same sender_id updates
the existing row instead of erroring, so the mobile app can safely
call this endpoint every time the local profile or contact list
changes, not just once.
"""

from fastapi import APIRouter, Depends, HTTPException, Request
from sqlalchemy.orm import Session

from app.core.rate_limit import register_ip_limiter, register_sender_limiter
from app.db.base import get_db
from app.models.user_profile import UserProfile
from app.schemas.user_profile import RegisterIn, RegisterOut
from app.services.request_auth import require_signed_body

router = APIRouter()


def _enforce_register_ip_limit(request: Request) -> None:
    register_ip_limiter.check(request)


@router.post("/register", response_model=RegisterOut)
def register_user(
    payload: RegisterIn,
    request: Request,
    _ip_limit: None = Depends(_enforce_register_ip_limit),
    signer: str = Depends(require_signed_body),
    db: Session = Depends(get_db),
):
    """
    Upsert a sender's profile. PROOF OF POSSESSION (Block 2): the request must
    be signed with the Ed25519 private key matching `sender_id`
    (X-Setu-* headers, see services/request_auth.py). Anyone who merely knows a
    public key -- which every mesh packet exposes -- can no longer overwrite
    that person's name, medical notes or emergency contacts.
    """
    register_sender_limiter.check(request, key=signer)
    if payload.sender_id != signer:
        raise HTTPException(status_code=403, detail="sender_id does not match the authenticated key.")

    existing = db.query(UserProfile).filter(
        UserProfile.sender_id == payload.sender_id
    ).first()

    if existing:
        # Upsert: the client always sends its full current local state
        # (see setu_app's ProfileSyncService), so a partial update is never expected.
        existing.name = payload.name
        existing.age = payload.age
        existing.gender = payload.gender
        existing.medical_history = payload.medical_history
        existing.emergency_contacts = payload.emergency_contacts
        db.commit()
        db.refresh(existing)
        return existing

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
