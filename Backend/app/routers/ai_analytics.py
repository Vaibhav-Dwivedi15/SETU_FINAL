from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.db.base import get_db
from app.services.ai_service import generate_habitation_narrative

router = APIRouter(prefix="/api/ai", tags=["AI Analytics"])

@router.get("/narrative/{habitation_id}")
def get_habitation_narrative(habitation_id: int, db: Session = Depends(get_db)):
    """
    Generates an AI-assisted narrative report for a habitation's risk profile.
    """
    try:
        return generate_habitation_narrative(db, habitation_id)
    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e))
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
