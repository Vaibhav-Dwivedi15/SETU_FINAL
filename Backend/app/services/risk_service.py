from typing import Dict, Any, List
from sqlalchemy.orm import Session
from app.models.gis_models import Habitation, HazardLayer, RiskAssessment
from app.services.gis_service import is_point_in_geojson_polygon
from app.services.data_quality_service import evaluate_habitation_quality

def calculate_habitation_risk(db: Session, habitation: Habitation, hazard_layers: List[HazardLayer]) -> RiskAssessment:
    """
    Deterministically calculates the risk for a single habitation against active hazard layers,
    incorporating historical disaster data and vulnerability.
    """
    dq_status, dq_reasons = evaluate_habitation_quality(db, habitation)
    
    total_score = 0.0
    factors = []
    hazard_breakdown = {}
    
    # Severity weighting
    severity_weights = {
        "critical": 10.0,
        "high": 7.0,
        "medium": 4.0,
        "low": 1.0
    }
    
    # 1. Multi-hazard exposure
    for layer in hazard_layers:
        if (layer.min_lat <= habitation.latitude <= layer.max_lat) and (layer.min_lon <= habitation.longitude <= layer.max_lon):
            if is_point_in_geojson_polygon(habitation.latitude, habitation.longitude, layer.geometry):
                weight = severity_weights.get(layer.severity.lower(), 0.0)
                total_score += weight
                hazard_breakdown[layer.hazard_type] = hazard_breakdown.get(layer.hazard_type, 0.0) + weight
                factors.append({
                    "factor_type": "hazard_exposure",
                    "hazard_type": layer.hazard_type,
                    "severity": layer.severity,
                    "score_contribution": weight,
                    "layer_id": layer.id
                })
                
    # 2. Disaster History integration
    from app.models.gis_models import DisasterHistory, VulnerabilityAssessment
    histories = db.query(DisasterHistory).filter(DisasterHistory.habitation_id == habitation.id).all()
    history_score = 0.0
    for h in histories:
        hw = severity_weights.get(h.intensity.lower(), 2.0)
        history_score += hw * 0.5  # History adds 50% of its severity to current risk
        factors.append({
            "factor_type": "historical_disaster",
            "hazard_type": h.hazard_type,
            "intensity": h.intensity,
            "score_contribution": hw * 0.5,
            "event_date": h.event_date.isoformat() if h.event_date else None
        })
    total_score += history_score
    
    # 3. Vulnerability amplification
    vuln = db.query(VulnerabilityAssessment).filter(VulnerabilityAssessment.habitation_id == habitation.id).first()
    if vuln:
        vuln_multiplier = 1.0 + (vuln.score / 20.0)  # Max +25% if score is 5.0
        total_score *= vuln_multiplier
        factors.append({
            "factor_type": "vulnerability_multiplier",
            "multiplier": vuln_multiplier,
            "vulnerability_score": vuln.score
        })
    

    # Determine risk level
    if total_score >= 15.0:
        risk_level = "Critical"
    elif total_score >= 8.0:
        risk_level = "High"
    elif total_score >= 4.0:
        risk_level = "Medium"
    else:
        risk_level = "Low"
        
    return RiskAssessment(
        habitation_id=habitation.id,
        score=round(total_score, 2),
        risk_level=risk_level,
        contributing_factors={
            "exposures": factors,
            "hazard_breakdown": hazard_breakdown,
            "methodology_version": "2.0",
            "formula": "Sum(active hazard weights) + Sum(history weights * 0.5) * Vulnerability multiplier"
        },
        data_quality=dq_status,
        data_quality_reasons=dq_reasons,
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
