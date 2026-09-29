from pydantic import BaseModel, Field
from typing import Optional, List, Dict, Any
from datetime import datetime

class DatasetBase(BaseModel):
    name: str
    is_demo: bool = False
    source: Optional[str] = None

class DatasetOut(DatasetBase):
    id: int
    created_at: datetime
    class Config:
        from_attributes = True

class HabitationBase(BaseModel):
    name: str
    district: str
    state: str
    population: Optional[int] = None
    latitude: float = Field(..., ge=-90, le=90)
    longitude: float = Field(..., ge=-180, le=180)
    boundary_geometry: Optional[Dict[str, Any]] = None

class HabitationOut(HabitationBase):
    id: int
    dataset_id: Optional[int]
    created_at: datetime
    updated_at: datetime
    class Config:
        from_attributes = True

class HabitationDetailOut(HabitationOut):
    dataset: Optional[DatasetOut] = None

class HazardLayerBase(BaseModel):
    hazard_type: str
    severity: str
    geometry: Dict[str, Any]
    source: Optional[str] = None
    geographic_coverage: Optional[str] = None
    data_type: Optional[str] = None

class HazardLayerOut(HazardLayerBase):
    id: int
    min_lat: float
    max_lat: float
    min_lon: float
    max_lon: float
    dataset_id: Optional[int]
    created_at: datetime
    class Config:
        from_attributes = True

class RiskAssessmentBase(BaseModel):
    score: float
    risk_level: str
    contributing_factors: Dict[str, Any]

class RiskAssessmentOut(RiskAssessmentBase):
    id: int
    habitation_id: int
    dataset_id: Optional[int]
    calculation_timestamp: datetime
    class Config:
        from_attributes = True

class VulnerabilityAssessmentOut(BaseModel):
    id: int
    habitation_id: int
    score: float
    factors: Dict[str, Any]
    dataset_id: Optional[int]
    calculation_timestamp: datetime
    class Config:
        from_attributes = True

class RelocationSiteBase(BaseModel):
    name: str
    district: str
    state: str
    latitude: float = Field(..., ge=-90, le=90)
    longitude: float = Field(..., ge=-180, le=180)
    geometry: Optional[Dict[str, Any]] = None
    usable_area_sqm: float
    infrastructure: Dict[str, Any]
    services: Dict[str, Any]
    current_occupancy: int = 0
    estimated_capacity: int
    remaining_capacity: int
    source: Optional[str] = None

class RelocationSiteOut(RelocationSiteBase):
    id: int
    dataset_id: Optional[int]
    created_at: datetime
    updated_at: datetime
    class Config:
        from_attributes = True

class RelocationRecommendationOut(BaseModel):
    id: int
    habitation_id: int
    site_id: int
    distance_km: float
    remaining_capacity: int
    suitable: bool
    reasons: List[str]
    priority_score: float
    dataset_id: Optional[int]
    created_at: datetime
    class Config:
        from_attributes = True

class PaginatedResponse(BaseModel):
    data: List[Any]
    pagination: Dict[str, int]
