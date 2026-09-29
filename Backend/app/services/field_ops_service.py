from sqlalchemy.orm import Session
from app.models.gis_models import FieldObservation, AuthorityDecision, Habitation, RelocationSite, HazardLayer
from app.services.recalculation_service import trigger_full_recalculation

def ingest_field_observation(db: Session, obs_data: dict, dataset_id: int) -> FieldObservation:
    """
    Ingests a field observation, applies the changes directly to the baseline models,
    and forces a recalculation of the dependency graph.
    """
    obs = FieldObservation(
        target_type=obs_data["target_type"],
        target_id=obs_data["target_id"],
        observation_type=obs_data["observation_type"],
        details=obs_data["details"],
        source=obs_data["source"],
        dataset_id=dataset_id
    )
    db.add(obs)
    
    # Apply changes
    if obs.target_type == "HABITATION":
        hab = db.query(Habitation).filter(Habitation.id == obs.target_id).first()
        if hab:
            if obs.observation_type == "POPULATION_CHANGED":
                hab.population = obs.details.get("population", hab.population)
            elif obs.observation_type == "ROAD_BLOCKED":
                hab.road_accessibility = False
    elif obs.target_type == "SITE":
        site = db.query(RelocationSite).filter(RelocationSite.id == obs.target_id).first()
        if site:
            if obs.observation_type == "CAPACITY_CHANGED":
                site.estimated_capacity = obs.details.get("estimated_capacity", site.estimated_capacity)
                site.current_occupancy = obs.details.get("current_occupancy", site.current_occupancy)
            elif obs.observation_type == "SITE_INACCESSIBLE":
                site.remaining_capacity = 0 # force rejection
    
    db.commit()
    db.refresh(obs)
    
    # Recalculate
    trigger_full_recalculation(db, dataset_id)
    
    return obs

def record_authority_decision(db: Session, dec_data: dict, dataset_id: int) -> AuthorityDecision:
    dec = AuthorityDecision(
        habitation_id=dec_data["habitation_id"],
        recommended_site_id=dec_data.get("recommended_site_id"),
        status=dec_data["status"],
        actor=dec_data["actor"],
        rationale=dec_data["rationale"],
        dataset_id=dataset_id
    )
    db.add(dec)
    db.commit()
    db.refresh(dec)
    return dec
