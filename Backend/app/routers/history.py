from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session
from typing import List, Optional
from datetime import datetime, timezone

from app.db.base import get_db
from app.models.gis_models import DisasterHistory, Habitation
from app.schemas.gis_schemas import DisasterHistoryOut, PaginatedResponse

router = APIRouter(prefix="/api/history", tags=["Disaster History"])

@router.get("", response_model=PaginatedResponse)
def get_history(
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=100),
    hazard_type: Optional[str] = None,
    db: Session = Depends(get_db)
):
    query = db.query(DisasterHistory)
    if hazard_type:
        query = query.filter(DisasterHistory.hazard_type == hazard_type)
        
    total = query.count()
    items = query.order_by(DisasterHistory.event_date.desc()).offset((page - 1) * page_size).limit(page_size).all()
    
    return {
        "data": items,
        "pagination": {
            "page": page,
            "page_size": page_size,
            "total": total,
            "total_pages": (total + page_size - 1) // page_size
        }
    }

@router.get("/habitations/{habitation_id}", response_model=PaginatedResponse)
def get_habitation_history(
    habitation_id: int,
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=100),
    db: Session = Depends(get_db)
):
    query = db.query(DisasterHistory).filter(DisasterHistory.habitation_id == habitation_id)
    total = query.count()
    items = query.order_by(DisasterHistory.event_date.desc()).offset((page - 1) * page_size).limit(page_size).all()
    
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
def get_history_summary(habitation_id: Optional[int] = None, db: Session = Depends(get_db)):
    query = db.query(DisasterHistory)
    if habitation_id:
        query = query.filter(DisasterHistory.habitation_id == habitation_id)
        
    all_events = query.all()
    
    summary = {
        "total_events": len(all_events),
        "hazard_breakdown": {},
        "severity_breakdown": {},
        "total_affected_population": 0,
        "latest_event_date": None,
        "event_frequency": len(all_events),  # Simple frequency, could be events/year
        "repeated_exposure": 0, # Habitations with >1 event
        "recency_days": None
    }
    
    habitation_counts = {}
    
    for event in all_events:
        summary["hazard_breakdown"][event.hazard_type] = summary["hazard_breakdown"].get(event.hazard_type, 0) + 1
        summary["severity_breakdown"][event.intensity] = summary["severity_breakdown"].get(event.intensity, 0) + 1
        if event.affected_population:
            summary["total_affected_population"] += event.affected_population
            
        if not summary["latest_event_date"] or (event.event_date.replace(tzinfo=timezone.utc) > summary["latest_event_date"].replace(tzinfo=timezone.utc)):
            summary["latest_event_date"] = event.event_date
            
        habitation_counts[event.habitation_id] = habitation_counts.get(event.habitation_id, 0) + 1
            
    summary["repeated_exposure"] = sum(1 for counts in habitation_counts.values() if counts > 1)
    
    if summary["latest_event_date"]:
        summary["recency_days"] = (datetime.now(timezone.utc) - summary["latest_event_date"].replace(tzinfo=timezone.utc)).days
            
    return summary
