from typing import List
from sqlalchemy.orm import Session
from app.models.gis_models import Habitation, RelocationSite, RelocationRecommendation, HazardLayer
from app.services.gis_service import calculate_haversine_distance, is_point_in_geojson_polygon

def generate_recommendations_for_habitation(db: Session, habitation: Habitation, sites: List[RelocationSite], hazards: List[HazardLayer], max_distance_km: float = 50.0):
    """
    Generates deterministic recommendations for a habitation to relocation sites.
    """
    recommendations = []
    
    for site in sites:
        reasons = []
        suitable = True
        priority_score = 0.0
        
        # 1. Distance check
        dist_km = calculate_haversine_distance(habitation.latitude, habitation.longitude, site.latitude, site.longitude)
        if dist_km > max_distance_km:
            suitable = False
            reasons.append(f"Outside configured relocation radius ({dist_km:.1f}km > {max_distance_km}km)")
        else:
            reasons.append(f"Within configured relocation radius ({dist_km:.1f}km)")
            priority_score += max(0, 10 - dist_km/5) # closer is better
            
        # 2. Capacity check
        if site.remaining_capacity < (habitation.population or 0):
            suitable = False
            reasons.append(f"Insufficient capacity ({site.remaining_capacity} remaining vs {habitation.population} population)")
        else:
            reasons.append("Sufficient remaining capacity")
            priority_score += 5.0
            
        # 3. Risk check for the site itself
        site_in_danger = False
        for layer in hazards:
            if (layer.min_lat <= site.latitude <= layer.max_lat) and (layer.min_lon <= site.longitude <= layer.max_lon):
                if is_point_in_geojson_polygon(site.latitude, site.longitude, layer.geometry):
                    if layer.severity.lower() in ['high', 'critical']:
                        site_in_danger = True
                        reasons.append(f"Inside high-risk hazard zone ({layer.hazard_type})")
        
        if site_in_danger:
            suitable = False
        else:
            reasons.append("Outside matching high-risk hazard zones")
            priority_score += 10.0
            
        # 4. Infrastructure/Service checks
        if site.infrastructure.get("road_access") == False:
            suitable = False
            reasons.append("Missing required road access")
            
        if site.services.get("medical_access") == True or site.services.get("hospital") == True:
            priority_score += 3.0
            
        rec = RelocationRecommendation(
            habitation_id=habitation.id,
            site_id=site.id,
            distance_km=dist_km,
            remaining_capacity=site.remaining_capacity,
            suitable=suitable,
            reasons=reasons,
            priority_score=priority_score if suitable else 0.0,
            dataset_id=habitation.dataset_id
        )
        recommendations.append(rec)
        
    return recommendations

def recalculate_all_recommendations(db: Session, dataset_id: int):
    db.query(RelocationRecommendation).filter(RelocationRecommendation.dataset_id == dataset_id).delete()
    
    habitations = db.query(Habitation).filter(Habitation.dataset_id == dataset_id).all()
    sites = db.query(RelocationSite).filter(RelocationSite.dataset_id == dataset_id).all()
    hazards = db.query(HazardLayer).filter(HazardLayer.dataset_id == dataset_id).all()
    
    new_recs = []
    for hab in habitations:
        recs = generate_recommendations_for_habitation(db, hab, sites, hazards)
        new_recs.extend(recs)
        
    db.add_all(new_recs)
    db.commit()
