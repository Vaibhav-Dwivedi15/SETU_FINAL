from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session
from typing import List, Any
import subprocess
import os

from app.db.base import get_db
from app.models.gis_models import Dataset
from app.schemas.gis_schemas import DatasetOut, PaginatedResponse

router = APIRouter(prefix="/api/datasets", tags=["Datasets"])

@router.get("", response_model=PaginatedResponse)
def get_datasets(
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=100),
    db: Session = Depends(get_db)
):
    query = db.query(Dataset)
    total = query.count()
    
    datasets = query.offset((page - 1) * page_size).limit(page_size).all()
    
    return {
        "data": datasets,
        "pagination": {
            "page": page,
            "page_size": page_size,
            "total": total,
            "total_pages": (total + page_size - 1) // page_size
        }
    }

from app.schemas.gis_schemas import DatasetCreate, HabitationCreate, HabitationOut, HazardLayerCreate, HazardLayerOut, RelocationSiteCreate, RelocationSiteOut
from app.models.gis_models import Habitation, HazardLayer, RelocationSite
from app.services.gis_service import get_bounding_box
from app.services.capacity_service import calculate_capacity

@router.post("", response_model=DatasetOut)
def create_dataset(dataset: DatasetCreate, db: Session = Depends(get_db)):
    db_dataset = Dataset(**dataset.dict())
    db.add(db_dataset)
    db.commit()
    db.refresh(db_dataset)
    return db_dataset

@router.post("/{id}/habitations", response_model=HabitationOut)
def add_habitation(id: int, habitation: HabitationCreate, db: Session = Depends(get_db)):
    dataset = db.query(Dataset).filter(Dataset.id == id).first()
    if not dataset:
        raise HTTPException(status_code=404, detail="Dataset not found")
    
    db_hab = Habitation(**habitation.dict(), dataset_id=id)
    db.add(db_hab)
    db.commit()
    db.refresh(db_hab)
    return db_hab

@router.post("/{id}/hazard-layers", response_model=HazardLayerOut)
def add_hazard_layer(id: int, layer: HazardLayerCreate, db: Session = Depends(get_db)):
    dataset = db.query(Dataset).filter(Dataset.id == id).first()
    if not dataset:
        raise HTTPException(status_code=404, detail="Dataset not found")
        
    min_lat, max_lat, min_lon, max_lon = get_bounding_box(layer.geometry)
    
    db_layer = HazardLayer(
        **layer.dict(),
        min_lat=min_lat,
        max_lat=max_lat,
        min_lon=min_lon,
        max_lon=max_lon,
        dataset_id=id
    )
    db.add(db_layer)
    db.commit()
    db.refresh(db_layer)
    return db_layer

@router.post("/{id}/relocation-sites", response_model=RelocationSiteOut)
def add_relocation_site(id: int, site: RelocationSiteCreate, db: Session = Depends(get_db)):
    dataset = db.query(Dataset).filter(Dataset.id == id).first()
    if not dataset:
        raise HTTPException(status_code=404, detail="Dataset not found")
        
    capacity_info = calculate_capacity(site.usable_area_sqm, site.current_occupancy)
    
    db_site = RelocationSite(
        **site.dict(),
        estimated_capacity=capacity_info["estimated_capacity"],
        remaining_capacity=capacity_info["remaining_capacity"],
        dataset_id=id
    )
    db.add(db_site)
    db.commit()
    db.refresh(db_site)
    return db_site

@router.post("/seed-demo")
def trigger_seed_demo():
    """
    Triggers the demo dataset seeder script.
    """
    script_path = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(__file__))), "scripts", "seed_demo_data.py")
    try:
        result = subprocess.run(["python", script_path], capture_output=True, text=True, check=True)
        return {"status": "success", "message": "Demo data seeded successfully.", "logs": result.stdout}
    except subprocess.CalledProcessError as e:
        raise HTTPException(status_code=500, detail=f"Seeding failed: {e.stderr}")
