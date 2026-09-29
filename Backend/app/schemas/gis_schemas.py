from pydantic import BaseModel, Field
from typing import Optional, List, Dict, Any
from datetime import datetime

class DatasetBase(BaseModel):
    name: str
    is_demo: bool = False
    is_scenario: bool = False
    source: Optional[str] = None
    data_timestamp: Optional[datetime] = None
    geographic_coverage: Optional[str] = None
    data_type: Optional[str] = None

class DatasetCreate(DatasetBase):
    pass

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
    vulnerable_population_count: int = 0
    infrastructure_score: float = 1.0
    healthcare_accessibility: bool = True
    road_accessibility: bool = True
    latitude: float = Field(..., ge=-90, le=90)
    longitude: float = Field(..., ge=-180, le=180)
    boundary_geometry: Optional[Dict[str, Any]] = None

class HabitationCreate(HabitationBase):
    pass

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

class HazardLayerCreate(HazardLayerBase):
    pass

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

class RedZoneAssessmentBase(BaseModel):
    classification: str
    confidence: str
    factors: Dict[str, Any]
    methodology_version: str

class RedZoneAssessmentOut(RedZoneAssessmentBase):
    id: int
    habitation_id: int
    dataset_id: Optional[int]
    assessment_timestamp: datetime
    class Config:
        from_attributes = True

class DisasterHistoryBase(BaseModel):
    habitation_id: int
    hazard_type: str
    event_date: datetime
    intensity: str
    affected_population: Optional[int] = None
    infrastructure_impact: Optional[str] = None
    duration_days: Optional[int] = None
    source: Optional[str] = None
    confidence: str = "HIGH"

class DisasterHistoryCreate(DisasterHistoryBase):
    pass

class DisasterHistoryOut(DisasterHistoryBase):
    id: int
    dataset_id: Optional[int]
    created_at: datetime
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
    source: Optional[str] = None

class RelocationSiteCreate(RelocationSiteBase):
    pass

class RelocationSiteOut(RelocationSiteBase):
    id: int
    estimated_capacity: int
    remaining_capacity: int
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
    priority_classification: Optional[str] = None
    dataset_id: Optional[int]
    created_at: datetime
    class Config:
        from_attributes = True

class RelocationAllocationOut(BaseModel):
    id: int
    habitation_id: int
    site_id: Optional[int]
    allocated_population: int
    allocation_status: str
    reasons: List[str]
    dataset_id: Optional[int]
    created_at: datetime
    class Config:
        from_attributes = True

class PaginatedResponse(BaseModel):
    data: List[Any]
    pagination: Dict[str, int]
