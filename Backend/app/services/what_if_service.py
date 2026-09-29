from sqlalchemy.orm import Session
from typing import Dict, Any, List
import copy
from app.models.gis_models import Dataset, Habitation, HazardLayer, RelocationSite, DisasterHistory, RelocationAllocation
from app.services.recalculation_service import trigger_full_recalculation

def create_what_if_scenario(db: Session, base_dataset_id: int, modifications: Dict[str, Any]) -> Dict[str, Any]:
    """
    Creates a temporary scenario dataset, applies modifications, calculates allocations, 
    and returns a diff against the baseline.
    
    modifications format:
    {
        "disabled_site_ids": [1, 2],
        "added_hazards": [{"type": "Polygon", "coordinates": [...]}]
    }
    """
    base_dataset = db.query(Dataset).filter(Dataset.id == base_dataset_id).first()
    if not base_dataset:
        raise ValueError("Base dataset not found")
        
    # 1. Clone Dataset
    scenario_dataset = Dataset(
        name=f"SCENARIO: {base_dataset.name}",
        source="What-If Engine",
        is_demo=True,
        is_scenario=True
    )
    db.add(scenario_dataset)
    db.commit()
    db.refresh(scenario_dataset)
    scen_id = scenario_dataset.id
    
    # 2. Clone Habitations
    habs = db.query(Habitation).filter(Habitation.dataset_id == base_dataset_id).all()
    hab_map = {} # map old id to new id
    for hab in habs:
        new_hab = Habitation(
            name=hab.name, district=hab.district, state=hab.state, population=hab.population,
            vulnerable_population_count=hab.vulnerable_population_count, infrastructure_score=hab.infrastructure_score,
            healthcare_accessibility=hab.healthcare_accessibility, road_accessibility=hab.road_accessibility,
            latitude=hab.latitude, longitude=hab.longitude, boundary_geometry=hab.boundary_geometry, dataset_id=scen_id
        )
        db.add(new_hab)
        db.flush()
        hab_map[hab.id] = new_hab.id
        
    # 3. Clone Sites, applying disabled_sites logic
    sites = db.query(RelocationSite).filter(RelocationSite.dataset_id == base_dataset_id).all()
    disabled_sites = modifications.get("disabled_site_ids", [])
    site_map = {}
    for site in sites:
        new_site = RelocationSite(
            name=site.name, district=site.district, state=site.state,
            latitude=site.latitude, longitude=site.longitude, usable_area_sqm=site.usable_area_sqm,
            infrastructure=site.infrastructure, services=site.services,
            current_occupancy=site.estimated_capacity if site.id in disabled_sites else site.current_occupancy, # Max out occupancy if disabled
            estimated_capacity=site.estimated_capacity,
            remaining_capacity=0 if site.id in disabled_sites else site.remaining_capacity,
            source=site.source, dataset_id=scen_id
        )
        db.add(new_site)
        db.flush()
        site_map[site.id] = new_site.id
        
    # 4. Clone History
    histories = db.query(DisasterHistory).filter(DisasterHistory.dataset_id == base_dataset_id).all()
    for hist in histories:
        new_hist = DisasterHistory(
            habitation_id=hab_map[hist.habitation_id], hazard_type=hist.hazard_type,
            event_date=hist.event_date, intensity=hist.intensity, affected_population=hist.affected_population,
            infrastructure_impact=hist.infrastructure_impact, duration_days=hist.duration_days,
            source=hist.source, dataset_id=scen_id
        )
        db.add(new_hist)
        
    # 5. Clone Hazards + Add new ones
    hazards = db.query(HazardLayer).filter(HazardLayer.dataset_id == base_dataset_id).all()
    for layer in hazards:
        new_layer = HazardLayer(
            hazard_type=layer.hazard_type, severity=layer.severity, geometry=layer.geometry,
            min_lat=layer.min_lat, max_lat=layer.max_lat, min_lon=layer.min_lon, max_lon=layer.max_lon,
            source=layer.source, dataset_id=scen_id
        )
        db.add(new_layer)
        
    added_hazards = modifications.get("added_hazards", [])
    from app.services.gis_service import get_bounding_box
    for ah in added_hazards:
        geom = ah["geometry"]
        min_lat, max_lat, min_lon, max_lon = get_bounding_box(geom)
        db.add(HazardLayer(
            hazard_type=ah.get("hazard_type", "synthetic"), severity=ah.get("severity", "critical"),
            geometry=geom, min_lat=min_lat, max_lat=max_lat, min_lon=min_lon, max_lon=max_lon,
            source="What-If Injection", dataset_id=scen_id
        ))
        
    db.commit()
    
    # 6. Run Engine
    trigger_full_recalculation(db, scen_id)
    
    # 7. Compute Diff (Allocations)
    base_allocs = db.query(RelocationAllocation).filter(RelocationAllocation.dataset_id == base_dataset_id).all()
    scen_allocs = db.query(RelocationAllocation).filter(RelocationAllocation.dataset_id == scen_id).all()
    
    # Map back scenario hab/site ids to original ids for comparison
    inv_hab_map = {v: k for k, v in hab_map.items()}
    inv_site_map = {v: k for k, v in site_map.items()}
    
    base_map = {a.habitation_id: a for a in base_allocs}
    
    impacted_habitations = []
    
    for s_alloc in scen_allocs:
        orig_hab_id = inv_hab_map[s_alloc.habitation_id]
        orig_site_id = inv_site_map[s_alloc.site_id] if s_alloc.site_id else None
        
        b_alloc = base_map.get(orig_hab_id)
        
        b_site_id = b_alloc.site_id if b_alloc else None
        
        if orig_site_id != b_site_id:
            impacted_habitations.append({
                "habitation_id": orig_hab_id,
                "baseline_site_id": b_site_id,
                "scenario_site_id": orig_site_id,
                "baseline_status": b_alloc.allocation_status if b_alloc else "NONE",
                "scenario_status": s_alloc.allocation_status,
                "reasoning": s_alloc.reasons
            })
            
    # Cleanup scenario dataset to keep DB clean (or keep if requested, but prompt says "DO NOT mutate production... Operate on a scenario copy")
    # For now, we leave it in the DB so user can query it, or we delete it. Let's delete it after diff to be stateless.
    # Actually, leaving it allows exploring the scenario via API. We'll leave it but it's marked is_scenario=True.
            
    return {
        "scenario_dataset_id": scen_id,
        "impacted_habitations_count": len(impacted_habitations),
        "impacted_habitations": impacted_habitations,
        "recommended_actions": [f"Review {len(impacted_habitations)} allocation changes."] if impacted_habitations else ["No impact observed."]
    }
