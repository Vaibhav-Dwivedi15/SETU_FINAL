from sqlalchemy.orm import Session
from app.services.risk_service import recalculate_all_risks
from app.services.vulnerability_service import recalculate_all_vulnerabilities
from app.services.red_zone_service import recalculate_all_red_zones
from app.services.relocation_service import recalculate_all_recommendations
from app.services.allocation_service import generate_allocations

def trigger_full_recalculation(db: Session, dataset_id: int):
    """
    Orchestrates the deterministic dependency chain for GIS analytical reassessment.
    When base data (habitations, hazards, history) changes, this ensures all derived
    assessments are correctly updated in order.
    
    Chain:
    1. Vulnerability (depends on habitation metadata + history)
    2. Risk (depends on hazards, history, and vulnerability)
    3. Red Zone (depends on risk and vulnerability)
    4. Relocation Priority (depends on habitation, risk, vulnerability, sites, hazards)
    5. Relocation Allocation (depends on capacities and relocation priorities)
    """
    # 1. Base vulnerabilities
    recalculate_all_vulnerabilities(db, dataset_id)
    
    # 2. Risk scoring
    recalculate_all_risks(db, dataset_id)
    
    # 3. Red Zone Classification
    recalculate_all_red_zones(db, dataset_id)
    
    # 4. Relocation Recommendations & Priorities
    recalculate_all_recommendations(db, dataset_id)
    
    # 5. Relocation Allocation
    generate_allocations(db, dataset_id)
    
    # Could potentially emit an event here in a fuller implementation.
    # For now, it synchronously guarantees data consistency.
