from sqlalchemy import Column, Integer, String, Float, Boolean, DateTime, ForeignKey, JSON
from sqlalchemy.orm import relationship
from datetime import datetime, timezone
from app.db.base import Base

class Dataset(Base):
    __tablename__ = "datasets"

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String, index=True)
    is_demo = Column(Boolean, default=False, index=True)
    is_scenario = Column(Boolean, default=False, index=True)
    source = Column(String)
    data_timestamp = Column(DateTime, nullable=True)
    geographic_coverage = Column(String, nullable=True)
    data_type = Column(String, nullable=True)
    created_at = Column(DateTime, default=lambda: datetime.now(timezone.utc))

class Habitation(Base):
    __tablename__ = "habitations"

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String, index=True)
    district = Column(String, index=True)
    state = Column(String, index=True)
    population = Column(Integer)
    vulnerable_population_count = Column(Integer, default=0) # elderly, children, disabled
    infrastructure_score = Column(Float, default=1.0) # 0-1, lower is worse
    healthcare_accessibility = Column(Boolean, default=True)
    road_accessibility = Column(Boolean, default=True)
    latitude = Column(Float, index=True)
    longitude = Column(Float, index=True)
    boundary_geometry = Column(JSON, nullable=True)  # GeoJSON
    dataset_id = Column(Integer, ForeignKey("datasets.id"), nullable=True)
    created_at = Column(DateTime, default=lambda: datetime.now(timezone.utc))
    updated_at = Column(DateTime, default=lambda: datetime.now(timezone.utc), onupdate=lambda: datetime.now(timezone.utc))

    dataset = relationship("Dataset")
    risk_assessments = relationship("RiskAssessment", back_populates="habitation")
    vulnerability_assessments = relationship("VulnerabilityAssessment", back_populates="habitation")

class HazardLayer(Base):
    __tablename__ = "hazard_layers"

    id = Column(Integer, primary_key=True, index=True)
    hazard_type = Column(String, index=True)  # flood, landslide, etc
    severity = Column(String, index=True) # low, medium, high, critical
    geometry = Column(JSON)  # GeoJSON polygon
    
    # Bounding box for fast spatial filtering
    min_lat = Column(Float, index=True)
    max_lat = Column(Float, index=True)
    min_lon = Column(Float, index=True)
    max_lon = Column(Float, index=True)
    
    source = Column(String)
    geographic_coverage = Column(String)
    data_type = Column(String)
    dataset_id = Column(Integer, ForeignKey("datasets.id"), nullable=True)
    created_at = Column(DateTime, default=lambda: datetime.now(timezone.utc))

    dataset = relationship("Dataset")

class RiskAssessment(Base):
    __tablename__ = "risk_assessments"

    id = Column(Integer, primary_key=True, index=True)
    habitation_id = Column(Integer, ForeignKey("habitations.id"), index=True)
    score = Column(Float)
    risk_level = Column(String, index=True) # Low, Medium, High, Critical
    contributing_factors = Column(JSON)
    data_quality = Column(String, default="VALID")
    data_quality_reasons = Column(JSON, default=list)
    dataset_id = Column(Integer, ForeignKey("datasets.id"), nullable=True)
    calculation_timestamp = Column(DateTime, default=lambda: datetime.now(timezone.utc))

    habitation = relationship("Habitation", back_populates="risk_assessments")
    dataset = relationship("Dataset")

class VulnerabilityAssessment(Base):
    __tablename__ = "vulnerability_assessments"

    id = Column(Integer, primary_key=True, index=True)
    habitation_id = Column(Integer, ForeignKey("habitations.id"), index=True)
    score = Column(Float)
    factors = Column(JSON)
    data_quality = Column(String, default="VALID")
    data_quality_reasons = Column(JSON, default=list)
    dataset_id = Column(Integer, ForeignKey("datasets.id"), nullable=True)
    calculation_timestamp = Column(DateTime, default=lambda: datetime.now(timezone.utc))

    habitation = relationship("Habitation", back_populates="vulnerability_assessments")
    dataset = relationship("Dataset")

class RedZoneAssessment(Base):
    __tablename__ = "red_zone_assessments"

    id = Column(Integer, primary_key=True, index=True)
    habitation_id = Column(Integer, ForeignKey("habitations.id"), index=True)
    classification = Column(String, index=True)  # GREEN, WATCH, HIGH_RISK, MODEL_ASSESSED_RED_ZONE
    confidence = Column(String)  # LOW, MEDIUM, HIGH
    factors = Column(JSON)
    methodology_version = Column(String)
    data_quality = Column(String, default="VALID")
    data_quality_reasons = Column(JSON, default=list)
    dataset_id = Column(Integer, ForeignKey("datasets.id"), nullable=True)
    assessment_timestamp = Column(DateTime, default=lambda: datetime.now(timezone.utc))

    habitation = relationship("Habitation")
    dataset = relationship("Dataset")

class DisasterHistory(Base):
    __tablename__ = "disaster_history"

    id = Column(Integer, primary_key=True, index=True)
    habitation_id = Column(Integer, ForeignKey("habitations.id"), index=True)
    hazard_type = Column(String, index=True)
    event_date = Column(DateTime)
    intensity = Column(String)  # LOW, MODERATE, HIGH, CRITICAL
    affected_population = Column(Integer, nullable=True)
    infrastructure_impact = Column(String, nullable=True)
    duration_days = Column(Integer, nullable=True)
    source = Column(String, nullable=True)
    confidence = Column(String, default="HIGH")  # Data quality label
    dataset_id = Column(Integer, ForeignKey("datasets.id"), nullable=True)
    created_at = Column(DateTime, default=lambda: datetime.now(timezone.utc))

    habitation = relationship("Habitation")
    dataset = relationship("Dataset")

class RelocationSite(Base):
    __tablename__ = "relocation_sites"

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String, index=True)
    district = Column(String, index=True)
    state = Column(String)
    latitude = Column(Float, index=True)
    longitude = Column(Float, index=True)
    geometry = Column(JSON, nullable=True)
    usable_area_sqm = Column(Float)
    infrastructure = Column(JSON)
    services = Column(JSON)
    
    current_occupancy = Column(Integer, default=0)
    estimated_capacity = Column(Integer)
    remaining_capacity = Column(Integer, index=True)
    
    source = Column(String)
    dataset_id = Column(Integer, ForeignKey("datasets.id"), nullable=True)
    created_at = Column(DateTime, default=lambda: datetime.now(timezone.utc))
    updated_at = Column(DateTime, default=lambda: datetime.now(timezone.utc), onupdate=lambda: datetime.now(timezone.utc))

    dataset = relationship("Dataset")

class RelocationRecommendation(Base):
    __tablename__ = "relocation_recommendations"

    id = Column(Integer, primary_key=True, index=True)
    habitation_id = Column(Integer, ForeignKey("habitations.id"), index=True)
    site_id = Column(Integer, ForeignKey("relocation_sites.id"), index=True)
    
    distance_km = Column(Float)
    remaining_capacity = Column(Integer)
    suitable = Column(Boolean, index=True)
    reasons = Column(JSON)
    priority_score = Column(Float, index=True)
    priority_classification = Column(String, index=True) # IMMEDIATE, SHORT_TERM, MEDIUM_TERM, MONITOR
    
    dataset_id = Column(Integer, ForeignKey("datasets.id"), nullable=True)
    created_at = Column(DateTime, default=lambda: datetime.now(timezone.utc))

    habitation = relationship("Habitation")
    site = relationship("RelocationSite")
    dataset = relationship("Dataset")

class RelocationAllocation(Base):
    __tablename__ = "relocation_allocations"
    
    id = Column(Integer, primary_key=True, index=True)
    habitation_id = Column(Integer, ForeignKey("habitations.id"), index=True)
    site_id = Column(Integer, ForeignKey("relocation_sites.id"), index=True)
    
    allocated_population = Column(Integer)
    allocation_status = Column(String, index=True) # FEASIBLE, PARTIAL, FAILED
    reasons = Column(JSON)
    
    dataset_id = Column(Integer, ForeignKey("datasets.id"), nullable=True)
    created_at = Column(DateTime, default=lambda: datetime.now(timezone.utc))
    
    habitation = relationship("Habitation")
    site = relationship("RelocationSite")
    dataset = relationship("Dataset")

class FieldObservation(Base):
    __tablename__ = "field_observations"
    
    id = Column(Integer, primary_key=True, index=True)
    target_type = Column(String, index=True) # HABITATION, SITE, HAZARD
    target_id = Column(Integer, index=True)
    observation_type = Column(String) # ROAD_BLOCKED, POPULATION_CHANGED, CAPACITY_CHANGED
    details = Column(JSON)
    source = Column(String)
    dataset_id = Column(Integer, ForeignKey("datasets.id"), nullable=True)
    created_at = Column(DateTime, default=lambda: datetime.now(timezone.utc))

class AuthorityDecision(Base):
    __tablename__ = "authority_decisions"
    
    id = Column(Integer, primary_key=True, index=True)
    habitation_id = Column(Integer, ForeignKey("habitations.id"), index=True)
    recommended_site_id = Column(Integer, ForeignKey("relocation_sites.id"), nullable=True)
    status = Column(String, index=True) # PROPOSED, ACCEPTED, MODIFIED, REJECTED, EXECUTED
    actor = Column(String)
    rationale = Column(String)
    dataset_id = Column(Integer, ForeignKey("datasets.id"), nullable=True)
    created_at = Column(DateTime, default=lambda: datetime.now(timezone.utc))
