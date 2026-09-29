from sqlalchemy.orm import Session
from app.models.gis_models import Habitation, RiskAssessment, VulnerabilityAssessment, RedZoneAssessment

from app.core import methodology_config as mconf

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
            methodology_version=mconf.METHODOLOGY_VERSION,
            data_quality="INCOMPLETE",
            data_quality_reasons=["Missing risk or vulnerability assessment"],
            dataset_id=habitation.dataset_id
        )
        
    factors["risk_level"] = risk.risk_level
    factors["risk_score"] = risk.score
    factors["vulnerability_score"] = vuln.score
    factors["methodology_name"] = mconf.METHODOLOGY_NAME
    
    # Red Zone classification logic
    if risk.risk_level == mconf.RED_ZONE_RISK_REQUIREMENT and vuln.score >= mconf.RED_ZONE_VULN_REQUIREMENT:
        classification = "MODEL_ASSESSED_RED_ZONE"
        factors["reason"] = f"Critical risk and extreme vulnerability (>={mconf.RED_ZONE_VULN_REQUIREMENT})"
    elif risk.risk_level == "Critical" or (risk.risk_level == "High" and vuln.score >= 70.0):
        classification = "HIGH_RISK"
        factors["reason"] = "Critical risk or High risk + high vulnerability"
    elif risk.risk_level == "High" or (risk.risk_level == "Medium" and vuln.score >= 40.0):
        classification = "WATCH"
        factors["reason"] = "Elevated risk profile"
    else:
        classification = "GREEN"
        factors["reason"] = "Low/acceptable risk profile"
        
    # Evaluate Data Quality for Red Zone
    dq_status = "VALID"
    dq_reasons = []
    
    if risk:
        if risk.data_quality != "VALID":
            dq_status = risk.data_quality
            dq_reasons.extend([f"Risk Assessment: {r}" for r in risk.data_quality_reasons])
    if vuln:
        if vuln.data_quality != "VALID":
            dq_status = vuln.data_quality if dq_status == "VALID" else dq_status # Keeps worst, but simplistic
            dq_reasons.extend([f"Vulnerability Assessment: {r}" for r in vuln.data_quality_reasons])
            
    if not dq_reasons:
        dq_reasons.append("Inputs are VALID")
        
    return RedZoneAssessment(
        habitation_id=habitation.id,
        classification=classification,
        confidence=confidence,
        factors=factors,
        methodology_version=mconf.METHODOLOGY_VERSION,
        data_quality=dq_status,
        data_quality_reasons=list(set(dq_reasons)), # remove duplicates
        dataset_id=habitation.dataset_id
    )

def recalculate_all_red_zones(db: Session, dataset_id: int):
    db.query(RedZoneAssessment).filter(RedZoneAssessment.dataset_id == dataset_id).delete()
    
    habitations = db.query(Habitation).filter(Habitation.dataset_id == dataset_id).all()
    assessments = [evaluate_red_zone(db, hab) for hab in habitations]
    
    db.add_all(assessments)
    db.commit()
