from typing import Dict, Any, Tuple
from app.core import methodology_config as mconf

def calculate_capacity(usable_area_sqm: float, occupancy: int, infrastructure: Dict[str, Any] = None, services: Dict[str, Any] = None, assumptions: Dict[str, Any] = None):
    """
    Capacity calculation modeled as a constrained resource problem.
    Calculates physical capacity, service capacity, and bottleneck-limited effective capacity.
    """
    infrastructure = infrastructure or {}
    services = services or {}
    
    if assumptions is None:
        assumptions = {
            "usable_area_ratio": mconf.CAPACITY_USABLE_AREA_RATIO,
            "area_per_person_sqm": mconf.CAPACITY_AREA_PER_PERSON_SQM,
            "water_lpd_per_person": mconf.CAPACITY_WATER_LITERS_PER_PERSON, # liters per day
            "sanitation_persons_per_toilet": mconf.CAPACITY_PERSONS_PER_TOILET,
            "formula": "min(physical, water, sanitation, healthcare)"
        }
    
    # 1. Physical Capacity
    effective_area = usable_area_sqm * assumptions.get("usable_area_ratio", 0.8)
    physical_capacity = int(effective_area / assumptions.get("area_per_person_sqm", 4.0))
    
    capacities = {"physical": physical_capacity}
    
    # 2. Infrastructure Constraints
    if "water_lpd" in infrastructure:
        capacities["water"] = int(infrastructure["water_lpd"] / assumptions.get("water_lpd_per_person", 15.0))
    
    if "toilets" in infrastructure:
        capacities["sanitation"] = int(infrastructure["toilets"] * assumptions.get("sanitation_persons_per_toilet", 20))
        
    if "healthcare_capacity_persons" in services:
        capacities["healthcare"] = int(services["healthcare_capacity_persons"])

    # 3. Determine Bottleneck
    bottleneck_resource = min(capacities, key=capacities.get)
    effective_capacity = capacities[bottleneck_resource]
    
    remaining_capacity = max(0, effective_capacity - occupancy)
    
    return {
        "usable_area_sqm": usable_area_sqm,
        "physical_capacity": physical_capacity,
        "effective_capacity": effective_capacity,
        "bottleneck": bottleneck_resource,
        "resource_capacities": capacities,
        "estimated_capacity": effective_capacity, # alias for backward compatibility
        "current_occupancy": occupancy,
        "remaining_capacity": remaining_capacity,
        "assumptions": assumptions
    }
