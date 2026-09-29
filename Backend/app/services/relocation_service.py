from typing import List
from sqlalchemy.orm import Session
from app.models.gis_models import Habitation, RelocationSite, RelocationRecommendation, HazardLayer
from app.services.gis_service import calculate_haversine_distance, is_point_in_geojson_polygon

def generate_recommendations_for_habitation(db: Session, habitation: Habitation, sites: List[RelocationSite], hazards: List[HazardLayer], max_distance_km: float = 50.0):
    """
    Generates deterministic recommendations for a habitation to relocation sites.
    """
    recommendations = []
    
    # Pre-fetch Risk and Vulnerability to determine habitation's baseline priority
    from app.models.gis_models import RiskAssessment, VulnerabilityAssessment, RedZoneAssessment
    risk_assmnt = db.query(RiskAssessment).filter(RiskAssessment.habitation_id == habitation.id).first()
    vuln_assmnt = db.query(VulnerabilityAssessment).filter(VulnerabilityAssessment.habitation_id == habitation.id).first()
    red_zone = db.query(RedZoneAssessment).filter(RedZoneAssessment.habitation_id == habitation.id).first()
    
    base_priority_score = 0.0
    habitation_danger = False
    
    if risk_assmnt:
        if risk_assmnt.risk_level.lower() == 'critical': 
            base_priority_score += 40.0
            habitation_danger = True
        elif risk_assmnt.risk_level.lower() == 'high': 
            base_priority_score += 25.0
            habitation_danger = True
        elif risk_assmnt.risk_level.lower() == 'medium': 
            base_priority_score += 10.0
            
    if vuln_assmnt:
        base_priority_score += (vuln_assmnt.score * 0.3)
        
    if red_zone and red_zone.classification in ["MODEL_ASSESSED_RED_ZONE", "HIGH_RISK"]:
        base_priority_score += 30.0
        habitation_danger = True
        
    if habitation.population:
        base_priority_score += min(20.0, habitation.population / 100.0)
    
    # Classify priority
    priority_class = "MONITOR"
    if base_priority_score >= 80.0 or habitation_danger:
        priority_class = "IMMEDIATE"
    elif base_priority_score >= 50.0:
        priority_class = "SHORT_TERM"
    elif base_priority_score >= 20.0:
        priority_class = "MEDIUM_TERM"
    
    for site in sites:
        reasons = []
        suitable = True
        site_score = 0.0
        
        # 1. Distance check
        dist_km = calculate_haversine_distance(habitation.latitude, habitation.longitude, site.latitude, site.longitude)
        if dist_km > max_distance_km:
            suitable = False
            reasons.append(f"INSUFFICIENT_DISTANCE: {dist_km:.1f}km > {max_distance_km}km")
        else:
            reasons.append(f"FEASIBLE_DISTANCE: {dist_km:.1f}km")
            site_score += max(0, 15.0 - (dist_km / 2.0)) # closer is better, up to 15 pts
            
        # 2. Capacity check
        if site.remaining_capacity < (habitation.population or 0):
            suitable = False
            reasons.append(f"INSUFFICIENT_CAPACITY: {site.remaining_capacity} remaining vs {habitation.population} required")
        else:
            reasons.append(f"FEASIBLE_CAPACITY: {site.remaining_capacity} available")
            site_score += 5.0
            
        # 3. Hazard safety check for the site itself
        site_in_danger = False
        for layer in hazards:
            if (layer.min_lat <= site.latitude <= layer.max_lat) and (layer.min_lon <= site.longitude <= layer.max_lon):
                if is_point_in_geojson_polygon(site.latitude, site.longitude, layer.geometry):
                    if layer.severity.lower() in ['high', 'critical']:
                        site_in_danger = True
                        reasons.append(f"HAZARD_EXPOSURE: Inside {layer.severity} risk {layer.hazard_type} zone")
        
        if site_in_danger:
            suitable = False
        else:
            reasons.append("HAZARD_SAFE: Site is outside high-risk zones")
            site_score += 20.0
            
        # 4. Infrastructure & Service Quality
        if site.infrastructure:
            if not site.infrastructure.get("road_access", True):
                suitable = False
                reasons.append("MISSING_INFRASTRUCTURE: No road access")
            if site.infrastructure.get("electricity"): site_score += 5.0
            if site.infrastructure.get("water_lpd", 0) > 10000: site_score += 5.0
            
        if site.services:
            if site.services.get("healthcare_capacity_persons", 0) > 0 or site.services.get("hospital"):
                site_score += 10.0
            if site.services.get("school"):
                site_score += 5.0
            
        final_priority = base_priority_score + site_score if suitable else 0.0
            
        rec = RelocationRecommendation(
            habitation_id=habitation.id,
            site_id=site.id,
            distance_km=dist_km,
            remaining_capacity=site.remaining_capacity,
            suitable=suitable,
            reasons=reasons,
            priority_score=round(final_priority, 2),
            priority_classification=priority_class if suitable else None,
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
