from typing import Dict, Any, List
from sqlalchemy.orm import Session
from app.models.gis_models import Habitation, HazardLayer, RiskAssessment
from app.services.gis_service import is_point_in_geojson_polygon

def calculate_habitation_risk(db: Session, habitation: Habitation, hazard_layers: List[HazardLayer]) -> RiskAssessment:
    """
    Deterministically calculates the risk for a single habitation against active hazard layers.
    """
    total_score = 0.0
    factors = []
    
    # Severity weighting
    severity_weights = {
        "critical": 10.0,
        "high": 7.0,
        "medium": 4.0,
        "low": 1.0
    }
    
    for layer in hazard_layers:
        # Bounding box filter first (fast)
        if (layer.min_lat <= habitation.latitude <= layer.max_lat) and (layer.min_lon <= habitation.longitude <= layer.max_lon):
            # Exact geometry check
            if is_point_in_geojson_polygon(habitation.latitude, habitation.longitude, layer.geometry):
                weight = severity_weights.get(layer.severity.lower(), 0.0)
                total_score += weight
                factors.append({
                    "hazard_type": layer.hazard_type,
                    "severity": layer.severity,
                    "score_contribution": weight,
                    "layer_id": layer.id
                })
    
    # Determine risk level
    if total_score >= 10.0:
        risk_level = "Critical"
    elif total_score >= 7.0:
        risk_level = "High"
    elif total_score >= 4.0:
        risk_level = "Medium"
    else:
        risk_level = "Low"
        
    return RiskAssessment(
        habitation_id=habitation.id,
        score=total_score,
        risk_level=risk_level,
        contributing_factors={"exposures": factors, "formula": "Sum of hazard severity weights (Critical=10, High=7, Medium=4, Low=1)"},
        dataset_id=habitation.dataset_id
    )

def recalculate_all_risks(db: Session, dataset_id: int):
    """
    Recalculates risk for all habitations in a dataset against all hazards in that dataset.
    """
    db.query(RiskAssessment).filter(RiskAssessment.dataset_id == dataset_id).delete()
    
    habitations = db.query(Habitation).filter(Habitation.dataset_id == dataset_id).all()
    hazards = db.query(HazardLayer).filter(HazardLayer.dataset_id == dataset_id).all()
    
    new_assessments = []
    for hab in habitations:
        assessment = calculate_habitation_risk(db, hab, hazards)
        new_assessments.append(assessment)
        
    db.add_all(new_assessments)
    db.commit()
