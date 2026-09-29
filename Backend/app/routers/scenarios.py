from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session
from typing import Dict, Any, List

from app.db.base import get_db
from app.models.gis_models import Dataset
from app.services.what_if_service import create_what_if_scenario

router = APIRouter(prefix="/api/scenarios", tags=["Scenarios"])

@router.post("/evaluate/{base_dataset_id}")
def evaluate_scenario(
    base_dataset_id: int,
    modifications: Dict[str, Any],
    db: Session = Depends(get_db)
):
    """
    Evaluates a what-if scenario.
    Modifications payload example:
    {
        "disabled_site_ids": [1, 5],
        "added_hazards": [
            {
                "hazard_type": "flood",
                "severity": "critical",
                "geometry": {"type": "Polygon", "coordinates": [...]}
            }
        ]
    }
    """
    try:
        result = create_what_if_scenario(db, base_dataset_id, modifications)
        return result
    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e))
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to evaluate scenario: {str(e)}")
