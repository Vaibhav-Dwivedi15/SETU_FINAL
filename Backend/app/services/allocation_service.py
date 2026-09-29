from sqlalchemy.orm import Session
from app.models.gis_models import RelocationRecommendation, RelocationAllocation, Habitation, RelocationSite

def generate_allocations(db: Session, dataset_id: int):
    """
    Deterministic constraint-based allocation engine.
    Assigns habitations to sites based on Priority Classification and exact capacity tracking.
    """
    # Clear old allocations
    db.query(RelocationAllocation).filter(RelocationAllocation.dataset_id == dataset_id).delete()
    
    # Get all habitations needing relocation, sorted by priority (assuming we derive priority from recommendations)
    # We will get the highest recommendation for each habitation to determine its overall priority queue order.
    habitations = db.query(Habitation).filter(Habitation.dataset_id == dataset_id).all()
    
    # Mapping of habitation to its max priority score so we can sort them
    hab_priorities = {}
    for hab in habitations:
        max_rec = db.query(RelocationRecommendation)\
                    .filter(RelocationRecommendation.habitation_id == hab.id, RelocationRecommendation.suitable == True)\
                    .order_by(RelocationRecommendation.priority_score.desc()).first()
        
        hab_priorities[hab.id] = max_rec.priority_score if max_rec else 0.0
        
    # Sort habitations by priority score descending
    sorted_habs = sorted(habitations, key=lambda h: hab_priorities.get(h.id, 0.0), reverse=True)
    
    # Track available capacity in memory to avoid constant DB queries during allocation loop
    sites = db.query(RelocationSite).filter(RelocationSite.dataset_id == dataset_id).all()
    site_capacity = {s.id: s.remaining_capacity for s in sites}
    
    allocations = []
    
    for hab in sorted_habs:
        pop_to_allocate = hab.population or 0
        if pop_to_allocate <= 0:
            continue
            
        # Get suitable recommendations for this habitation, ordered by priority
        recs = db.query(RelocationRecommendation)\
                 .filter(RelocationRecommendation.habitation_id == hab.id, RelocationRecommendation.suitable == True)\
                 .order_by(RelocationRecommendation.priority_score.desc()).all()
                 
        if not recs:
            allocations.append(RelocationAllocation(
                habitation_id=hab.id,
                site_id=None,
                allocated_population=0,
                allocation_status="FAILED",
                reasons=["No suitable candidate sites available for this habitation."],
                dataset_id=dataset_id
            ))
            continue
            
        allocated = False
        
        for rec in recs:
            available = site_capacity.get(rec.site_id, 0)
            if available >= pop_to_allocate:
                # Fully allocate here
                site_capacity[rec.site_id] -= pop_to_allocate
                allocations.append(RelocationAllocation(
                    habitation_id=hab.id,
                    site_id=rec.site_id,
                    allocated_population=pop_to_allocate,
                    allocation_status="FEASIBLE",
                    reasons=[f"Successfully allocated entire population ({pop_to_allocate}) to {rec.site.name}."],
                    dataset_id=dataset_id
                ))
                allocated = True
                break
            elif available > 0:
                # Partially allocate here and continue
                site_capacity[rec.site_id] -= available
                pop_to_allocate -= available
                allocations.append(RelocationAllocation(
                    habitation_id=hab.id,
                    site_id=rec.site_id,
                    allocated_population=available,
                    allocation_status="PARTIAL",
                    reasons=[f"Partially allocated {available} people to {rec.site.name} (Site reached maximum capacity)."],
                    dataset_id=dataset_id
                ))
                
        if not allocated and pop_to_allocate > 0:
            allocations.append(RelocationAllocation(
                habitation_id=hab.id,
                site_id=None,
                allocated_population=0,
                allocation_status="FAILED",
                reasons=[f"Failed to allocate remaining {pop_to_allocate} people (All suitable sites reached maximum capacity)."],
                dataset_id=dataset_id
            ))
            
    db.add_all(allocations)
    db.commit()
