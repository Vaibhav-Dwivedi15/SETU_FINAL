from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session
from typing import List, Optional

from app.db.base import get_db
from app.models.gis_models import RelocationSite, RelocationRecommendation
from app.schemas.gis_schemas import RelocationSiteOut, RelocationRecommendationOut, PaginatedResponse

router = APIRouter(prefix="/api/relocation", tags=["Relocation"])

@router.get("/sites", response_model=PaginatedResponse)
def get_sites(
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=100),
    district: Optional[str] = None,
    min_capacity: Optional[int] = None,
    db: Session = Depends(get_db)
):
    query = db.query(RelocationSite)
    if district:
        query = query.filter(RelocationSite.district == district)
    if min_capacity is not None:
        query = query.filter(RelocationSite.remaining_capacity >= min_capacity)
        
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

@router.get("/sites/{id}", response_model=RelocationSiteOut)
def get_site(id: int, db: Session = Depends(get_db)):
    site = db.query(RelocationSite).filter(RelocationSite.id == id).first()
    if not site:
        raise HTTPException(status_code=404, detail={"code": "NOT_FOUND", "message": "Relocation site not found."})
    return site

@router.get("/sites/{id}/capacity")
def get_site_capacity(id: int, db: Session = Depends(get_db)):
    site = db.query(RelocationSite).filter(RelocationSite.id == id).first()
    if not site:
        raise HTTPException(status_code=404, detail={"code": "NOT_FOUND", "message": "Relocation site not found."})
    
    from app.services.capacity_service import calculate_capacity
    return calculate_capacity(
        usable_area_sqm=site.usable_area_sqm,
        occupancy=site.current_occupancy,
        infrastructure=site.infrastructure,
        services=site.services
    )

@router.get("/recommendations/{habitation_id}", response_model=PaginatedResponse)
def get_recommendations(
    habitation_id: int,
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=100),
    db: Session = Depends(get_db)
):
    query = db.query(RelocationRecommendation).filter(RelocationRecommendation.habitation_id == habitation_id)
    query = query.order_by(RelocationRecommendation.priority_score.desc())
    
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

@router.get("/priorities", response_model=PaginatedResponse)
def get_priorities(
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=100),
    db: Session = Depends(get_db)
):
    # Returns the highest priority recommendations overall
    query = db.query(RelocationRecommendation).filter(RelocationRecommendation.suitable == True)
    query = query.order_by(RelocationRecommendation.priority_score.desc())
    
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
def get_relocation_summary(db: Session = Depends(get_db)):
    total_sites = db.query(RelocationSite).count()
    
    sites = db.query(RelocationSite).all()
    total_capacity = sum(s.estimated_capacity for s in sites if s.estimated_capacity)
    occupied_capacity = sum(s.current_occupancy for s in sites if s.current_occupancy)
    remaining_capacity = sum(s.remaining_capacity for s in sites if s.remaining_capacity)
    
    total_recommendations = db.query(RelocationRecommendation).count()
    
    return {
        "total_relocation_sites": total_sites,
        "total_capacity": total_capacity,
        "occupied_capacity": occupied_capacity,
        "remaining_capacity": remaining_capacity,
        "recommendations_generated": total_recommendations
    }

@router.get("/allocations", response_model=PaginatedResponse)
def get_allocations(
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=100),
    db: Session = Depends(get_db)
):
    from app.models.gis_models import RelocationAllocation
    query = db.query(RelocationAllocation)
    
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
