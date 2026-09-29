from sqlalchemy.orm import Session
from datetime import datetime, timedelta, timezone
from app.models.gis_models import Habitation, Dataset, HazardLayer

def evaluate_habitation_quality(db: Session, habitation: Habitation) -> tuple[str, list[str]]:
    """
    Evaluates the input data quality for a given habitation.
    Returns (status, list_of_reasons).
    Status can be: VALID, STALE, INCOMPLETE, LOW_CONFIDENCE
    """
    reasons = []
    status = "VALID"
    
    # 1. Check habitation completeness
    if not habitation.population:
        reasons.append("Missing explicit population count (assumed 0)")
        status = "INCOMPLETE"
        
    if habitation.vulnerable_population_count is None:
        reasons.append("Missing vulnerable population breakdown")
        if status == "VALID": status = "LOW_CONFIDENCE"
        
    # 2. Check dataset staleness
    dataset = db.query(Dataset).filter(Dataset.id == habitation.dataset_id).first()
    if dataset and dataset.data_timestamp:
        age_days = (datetime.now(timezone.utc) - dataset.data_timestamp.replace(tzinfo=timezone.utc)).days
        if age_days > 365:
            reasons.append(f"Habitation dataset is stale ({age_days} days old)")
            status = "STALE" if status in ["VALID", "LOW_CONFIDENCE"] else status
            
    # 3. Check hazard data staleness
    # We'll just check if there are any hazards for this dataset and their age.
    hazards = db.query(HazardLayer).filter(HazardLayer.dataset_id == habitation.dataset_id).all()
    if not hazards:
        reasons.append("No hazard layers available for intersection")
        status = "INCOMPLETE"
    else:
        # Check if any hazard is stale (source dataset timestamp or created_at)
        stale_hazards = False
        for h in hazards:
            if h.created_at:
                h_age = (datetime.now(timezone.utc) - h.created_at.replace(tzinfo=timezone.utc)).days
                if h_age > 180: # Hazard data expires faster
                    stale_hazards = True
        
        if stale_hazards:
            reasons.append("Hazard layer data is older than 6 months (stale)")
            status = "STALE" if status in ["VALID", "LOW_CONFIDENCE"] else status
            
    if not reasons:
        reasons.append("All input dimensions are current and fully specified.")
            
    return status, reasons
