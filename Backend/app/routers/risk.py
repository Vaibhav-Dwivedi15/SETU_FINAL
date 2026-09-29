from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session
from typing import List, Optional

from app.db.base import get_db
from app.models.gis_models import Habitation, RiskAssessment, HazardLayer, Dataset
from app.schemas.gis_schemas import HabitationOut, HabitationDetailOut, RiskAssessmentOut, HazardLayerOut, PaginatedResponse

router = APIRouter(prefix="/api/risk", tags=["Risk"])

@router.get("/habitations", response_model=PaginatedResponse)
def get_habitations(
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=100),
    district: Optional[str] = None,
    db: Session = Depends(get_db)
):
    query = db.query(Habitation)
    if district:
        query = query.filter(Habitation.district == district)
        
    total = query.count()
    items = query.offset((page - 1) * page_size).limit(page_size).all()
    
    # Eager load dataset or handle it
    
    return {
        "data": items,
        "pagination": {
            "page": page,
            "page_size": page_size,
            "total": total,
            "total_pages": (total + page_size - 1) // page_size
        }
    }

@router.get("/habitations/{id}", response_model=HabitationDetailOut)
def get_habitation(id: int, db: Session = Depends(get_db)):
    hab = db.query(Habitation).filter(Habitation.id == id).first()
    if not hab:
        raise HTTPException(status_code=404, detail={"code": "NOT_FOUND", "message": "Habitation not found."})
    return hab

@router.get("/zones", response_model=PaginatedResponse)
def get_hazard_zones(
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=100),
    hazard_type: Optional[str] = None,
    db: Session = Depends(get_db)
):
    query = db.query(HazardLayer)
    if hazard_type:
        query = query.filter(HazardLayer.hazard_type == hazard_type)
        
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

@router.get("/layers", response_model=PaginatedResponse)
def get_layers(page: int = 1, page_size: int = 20, db: Session = Depends(get_db)):
    return get_hazard_zones(page, page_size, None, db)

@router.get("/summary")
def get_risk_summary(db: Session = Depends(get_db)):
    total_habitations = db.query(Habitation).count()
    critical = db.query(RiskAssessment).filter(RiskAssessment.risk_level == 'Critical').count()
    high = db.query(RiskAssessment).filter(RiskAssessment.risk_level == 'High').count()
    medium = db.query(RiskAssessment).filter(RiskAssessment.risk_level == 'Medium').count()
    low = db.query(RiskAssessment).filter(RiskAssessment.risk_level == 'Low').count()
    
    hazards_count = db.query(HazardLayer).count()
    
    return {
        "total_habitations": total_habitations,
        "risk_breakdown": {
            "critical": critical,
            "high": high,
            "medium": medium,
            "low": low
        },
        "total_hazard_layers": hazards_count
    }
