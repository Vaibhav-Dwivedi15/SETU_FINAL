"""
Responder registry endpoints.

POST/GET /responders: admin/internal only -- gated by the same responder
API-key check used for the dashboard, since provisioning a trusted
responder is a privileged action. Separate from POST /register (citizen
profile registration), which stays open and unauthenticated.

GET /responders/keys: deliberately public/unauthenticated -- this is the
contract Vaibhav's mesh layer polls (every 5 min + on app startup) to
verify a TerminationPacket's SENDER (sender_id) client-side, before a
termination is even relayed. Same open-access pattern as /ingest,
different from the two routes above since the content here (public
keys) is meant to be public. See app/schemas/responder.py and
app/models/responder.py for why this is keyed on public_key, not any
packet-level responder_id field.
"""

from typing import List

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.core.rate_limit import enforce_responder_action_rate_limit, enforce_responder_keys_rate_limit
from app.core.security import verify_responder_api_key
from app.db.base import get_db
from app.models.responder import ResponderProfile
from app.schemas.responder import ResponderIn, ResponderOut, ResponderKeysOut

router = APIRouter()


@router.post("/responders", response_model=ResponderOut)
def register_responder(
    payload: ResponderIn,
    db: Session = Depends(get_db),
    _: None = Depends(verify_responder_api_key),
    # SEP 2026: rate-limited on top of the API-key gate -- provisioning a
    # new trusted responder key is the single most sensitive write in
    # this API (that key can later authorize TerminationPacket
    # acceptance mesh-wide), so it gets the "RESPONDER ACTION -> strict"
    # tier even though it is already authenticated. Defense in depth: a
    # leaked/guessed key still can't be used to script rapid-fire
    # provisioning.
    _rate_limit: None = Depends(enforce_responder_action_rate_limit),
):
    existing = db.query(ResponderProfile).filter(
        ResponderProfile.public_key == payload.public_key
    ).first()
    if existing:
        raise HTTPException(
            status_code=409,
            detail=f"public_key '{payload.public_key}' is already registered.",
        )

    responder = ResponderProfile(
        public_key=payload.public_key,
        name=payload.name,
        organization=payload.organization,
    )
    db.add(responder)
    db.commit()
    db.refresh(responder)
    return responder


@router.get("/responders", response_model=List[ResponderOut])
def list_responders(
    db: Session = Depends(get_db),
    _: None = Depends(verify_responder_api_key),
):
    return db.query(ResponderProfile).all()


@router.get("/responders/keys", response_model=ResponderKeysOut)
def list_responder_public_keys(
    db: Session = Depends(get_db),
    _rate_limit: None = Depends(enforce_responder_keys_rate_limit),
):
    """
    Public, unauthenticated -- consumed by mesh relay devices to verify
    a TerminationPacket's sender_id before honoring it client-side.

    Only active responders are included -- revoking a responder
    (is_active=False) means their key drops out of the NEXT mesh sync,
    since Vaibhav's side does a full replace (syncFromBackend), not an
    additive merge.

    Returns an empty list, not a 404, when no responders are onboarded
    yet -- the mesh side already treats [] the same as "not synced"
    (fails open with a warning), so this is the expected/preferred shape
    per the contract, not an error case.
    """
    active_responders = (
        db.query(ResponderProfile)
        .filter(ResponderProfile.is_active.is_(True))
        .all()
    )
    return {"responder_public_keys": [r.public_key for r in active_responders]}