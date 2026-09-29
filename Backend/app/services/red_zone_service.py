from sqlalchemy.orm import Session
from app.models.gis_models import Habitation, RiskAssessment, VulnerabilityAssessment, RedZoneAssessment

def evaluate_red_zone(db: Session, habitation: Habitation) -> RedZoneAssessment:
    """
    Evaluates whether a habitation is a Red Zone based on:
    - Risk (Hazard exposure + History)
    - Vulnerability
    """
    risk = db.query(RiskAssessment).filter(RiskAssessment.habitation_id == habitation.id).first()
    vuln = db.query(VulnerabilityAssessment).filter(VulnerabilityAssessment.habitation_id == habitation.id).first()
    
    factors = {}
    classification = "GREEN"
    confidence = "HIGH"
    
    if not risk or not vuln:
        confidence = "LOW"
        factors["missing_data"] = "Missing risk or vulnerability assessment"
        return RedZoneAssessment(
            habitation_id=habitation.id,
            classification=classification,
            confidence=confidence,
            factors=factors,
            methodology_version="1.0",
            dataset_id=habitation.dataset_id
        )
        
    factors["risk_level"] = risk.risk_level
    factors["risk_score"] = risk.score
    factors["vulnerability_score"] = vuln.score
    
    # Red Zone classification logic
    # Using MODEL_ASSESSED_RED_ZONE as required
    if risk.risk_level == "Critical" and vuln.score >= 50.0:
        classification = "MODEL_ASSESSED_RED_ZONE"
        factors["reason"] = "Critical risk and extreme vulnerability"
    elif risk.risk_level == "Critical" or (risk.risk_level == "High" and vuln.score >= 70.0):
        classification = "HIGH_RISK"
        factors["reason"] = "Critical risk or High risk + high vulnerability"
    elif risk.risk_level == "High" or (risk.risk_level == "Medium" and vuln.score >= 40.0):
        classification = "WATCH"
        factors["reason"] = "Elevated risk profile"
    else:
        classification = "GREEN"
        factors["reason"] = "Low/acceptable risk profile"
        
    return RedZoneAssessment(
        habitation_id=habitation.id,
        classification=classification,
        confidence=confidence,
        factors=factors,
        methodology_version="1.0",
        dataset_id=habitation.dataset_id
    )

def recalculate_all_red_zones(db: Session, dataset_id: int):
    db.query(RedZoneAssessment).filter(RedZoneAssessment.dataset_id == dataset_id).delete()
    
    habitations = db.query(Habitation).filter(Habitation.dataset_id == dataset_id).all()
    assessments = [evaluate_red_zone(db, hab) for hab in habitations]
    
    db.add_all(assessments)
    db.commit()
