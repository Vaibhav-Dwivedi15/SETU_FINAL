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
