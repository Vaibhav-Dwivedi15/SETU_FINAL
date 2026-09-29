from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from typing import Dict, Any

from app.db.base import get_db
from app.services.field_ops_service import ingest_field_observation, record_authority_decision
from app.schemas.gis_schemas import FieldObservationBase, FieldObservationOut, AuthorityDecisionBase, AuthorityDecisionOut

router = APIRouter(prefix="/api/field", tags=["Field Operations"])

@router.post("/observations/{dataset_id}", response_model=FieldObservationOut)
def create_observation(dataset_id: int, obs: FieldObservationBase, db: Session = Depends(get_db)):
    try:
        # We simulate Pydantic v2 `model_dump()` behavior, or just dict() depending on versions
        obs_dict = obs.dict() if hasattr(obs, 'dict') else obs.model_dump()
        return ingest_field_observation(db, obs_dict, dataset_id)
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@router.post("/decisions/{dataset_id}", response_model=AuthorityDecisionOut)
def create_decision(dataset_id: int, dec: AuthorityDecisionBase, db: Session = Depends(get_db)):
    try:
        dec_dict = dec.dict() if hasattr(dec, 'dict') else dec.model_dump()
        return record_authority_decision(db, dec_dict, dataset_id)
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
