from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session
from typing import Optional

from app.db.base import get_db
from app.models.gis_models import RedZoneAssessment
from app.schemas.gis_schemas import RedZoneAssessmentOut, PaginatedResponse

router = APIRouter(prefix="/api/red-zones", tags=["Red Zones"])

@router.get("", response_model=PaginatedResponse)
def get_red_zones(
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=100),
    classification: Optional[str] = None,
    db: Session = Depends(get_db)
):
    query = db.query(RedZoneAssessment)
    if classification:
        query = query.filter(RedZoneAssessment.classification == classification)
        
    total = query.count()
    items = query.offset((page - 1) * page_size).limit(page_size).all()
    
    return {
        "data": items,
        "pagination": {
            "page": page,
            "page_size": page_size,
            "total": total,
            "total_pages": (total + page_size - 1) // page_size
        }
    }

@router.get("/summary")
def get_red_zones_summary(db: Session = Depends(get_db)):
    assessments = db.query(RedZoneAssessment).all()
    
    summary = {
        "total": len(assessments),
        "breakdown": {}
    }
    
    for a in assessments:
        summary["breakdown"][a.classification] = summary["breakdown"].get(a.classification, 0) + 1
        
    return summary
