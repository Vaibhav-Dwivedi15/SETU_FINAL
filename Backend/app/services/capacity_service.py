from typing import Dict, Any

def calculate_capacity(usable_area_sqm: float, occupancy: int, assumptions: Dict[str, Any] = None):
    """
    Capacity calculation that never uses magic numbers.
    """
    if assumptions is None:
        assumptions = {
            "usable_area_ratio": 0.8,
            "area_per_person_sqm": 4.0,
            "formula": "(usable_area_sqm * usable_area_ratio) / area_per_person_sqm"
        }
    
    effective_area = usable_area_sqm * assumptions.get("usable_area_ratio", 0.8)
    estimated_capacity = int(effective_area / assumptions.get("area_per_person_sqm", 4.0))
    remaining_capacity = max(0, estimated_capacity - occupancy)
    
    return {
        "usable_area_sqm": usable_area_sqm,
        "estimated_capacity": estimated_capacity,
        "current_occupancy": occupancy,
        "remaining_capacity": remaining_capacity,
        "assumptions": assumptions
    }
