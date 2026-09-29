import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.main import app
from app.db.base import Base, get_db

# Create an in-memory SQLite database
SQLALCHEMY_DATABASE_URL = "sqlite:///:memory:"

engine = create_engine(
    SQLALCHEMY_DATABASE_URL,
    connect_args={"check_same_thread": False},
    poolclass=StaticPool,
)
TestingSessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
from app.models import gis_models
Base.metadata.create_all(bind=engine)

def override_get_db():
    try:
        db = TestingSessionLocal()
        yield db
    finally:
        db.close()

@pytest.fixture
def client():
    app.dependency_overrides[get_db] = override_get_db
    c = TestClient(app)
    yield c
    app.dependency_overrides.clear()
    Base.metadata.drop_all(bind=engine)
    Base.metadata.create_all(bind=engine)

def test_gis_routers_loaded(client):
    """
    Ensures the GIS endpoints are at least registered in the app.
    """
    resp = client.get("/api/datasets")
    assert resp.status_code == 200
    
    resp = client.get("/api/risk/summary")
    assert resp.status_code == 200

def test_risk_calculation(client):
    """
    Check if the seeded data produces expected risk results.
    """
    db = TestingSessionLocal()
    from app.models.gis_models import Habitation, Dataset, HazardLayer
    from app.services.risk_service import recalculate_all_risks
    
    dataset = Dataset(name="Test", is_demo=True)
    db.add(dataset)
    db.commit()
    
    hab = Habitation(name="Test Hab", district="D1", state="S1", latitude=10.0, longitude=20.0, dataset_id=dataset.id)
    db.add(hab)
    
    hl = HazardLayer(hazard_type="flood", severity="high", geometry={"type":"Polygon", "coordinates":[[[19.0, 9.0], [21.0, 9.0], [21.0, 11.0], [19.0, 11.0], [19.0, 9.0]]]}, min_lat=9.0, max_lat=11.0, min_lon=19.0, max_lon=21.0, dataset_id=dataset.id)
    db.add(hl)
    db.commit()
    
    from app.services.recalculation_service import trigger_full_recalculation
    trigger_full_recalculation(db, dataset.id)
    
    resp = client.get("/api/risk/summary")
    assert resp.status_code == 200
    data = resp.json()
    assert data["total_habitations"] >= 1
    assert data["total_hazard_layers"] >= 1
    
    resp = client.get(f"/api/risk/habitations/{hab.id}")
    assert resp.status_code == 200
    data = resp.json()
    assert "risk_assessments" in data
    assert len(data["risk_assessments"]) > 0
    risk = data["risk_assessments"][0]
    assert "data_quality" in risk
    assert "data_quality_reasons" in risk
    
def test_relocation_recommendations(client):
    """
    Check that recommendations are returned for the seeded data.
    """
    resp = client.get("/api/relocation/summary")
    assert resp.status_code == 200
    
    resp = client.get("/api/relocation/priorities")
    assert resp.status_code == 200
    data = resp.json()
    if data["data"]:
        rec = data["data"][0]
        assert "priority_classification" in rec
        assert "priority_score" in rec
        assert "reasons" in rec

def test_vulnerability(client):
    """
    Check that vulnerability calculations are returned.
    """
    resp = client.get("/api/vulnerability/summary")
    assert resp.status_code == 200

def test_ingestion_and_capacity(client):
    """
    Check that ingestion endpoints work and capacity calculation is exposed.
    """
    # Create dataset
    resp = client.post("/api/datasets", json={"name": "Test Ingestion", "data_type": "official"})
    assert resp.status_code == 200
    dataset_id = resp.json()["id"]
    
    # Create habitation
    hab_payload = {
        "name": "Ingested Hab",
        "district": "Ingest District",
        "state": "State",
        "latitude": 10.0,
        "longitude": 20.0
    }
    resp = client.post(f"/api/datasets/{dataset_id}/habitations", json=hab_payload)
    assert resp.status_code == 200
    
    # Create relocation site
    site_payload = {
        "name": "Ingested Site",
        "district": "Ingest District",
        "state": "State",
        "latitude": 11.0,
        "longitude": 21.0,
        "usable_area_sqm": 5000.0,
        "infrastructure": {},
        "services": {},
        "current_occupancy": 100
    }
    resp = client.post(f"/api/datasets/{dataset_id}/relocation-sites", json=site_payload)
    assert resp.status_code == 200
    site_id = resp.json()["id"]
    
    # Check capacity endpoint
    resp = client.get(f"/api/relocation/sites/{site_id}/capacity")
    assert resp.status_code == 200
    data = resp.json()
    assert "assumptions" in data
    assert "estimated_capacity" in data
    assert data["estimated_capacity"] > 0
    assert data["remaining_capacity"] == data["estimated_capacity"] - 100

def test_disaster_history(client):
    """
    Check that history endpoints return expected derived indicators.
    """
    resp = client.get("/api/history/summary")
    assert resp.status_code == 200
    data = resp.json()
    assert "total_events" in data
    assert "recency_days" in data
    assert "repeated_exposure" in data
    assert "event_frequency" in data
    
    resp = client.get("/api/history")
    assert resp.status_code == 200

def test_red_zones(client):
    """
    Check that Red Zone classification endpoints return expected data.
    """
    resp = client.get("/api/red-zones/summary")
    assert resp.status_code == 200
    data = resp.json()
    assert "total" in data
    assert "breakdown" in data
    
    resp = client.get("/api/red-zones")
    assert resp.status_code == 200
    data = resp.json()
    assert "data" in data
    assert isinstance(data["data"], list)

def test_allocations_and_scenarios(client):
    """
    Check that allocations are generated and what-if scenarios evaluate successfully.
    """
    # Verify allocations route
    resp = client.get("/api/relocation/allocations")
    assert resp.status_code == 200
    
    # We need a dataset ID to test what-if
    # Creating a quick dataset directly
    db = TestingSessionLocal()
    from app.models.gis_models import Dataset
    dataset = Dataset(name="WhatIfBase", is_demo=True)
    db.add(dataset)
    db.commit()
    dataset_id = dataset.id
    
    # Test scenario evaluation
    scenario_payload = {
        "disabled_site_ids": [1],
        "added_hazards": []
    }
    resp = client.post(f"/api/scenarios/evaluate/{dataset_id}", json=scenario_payload)
    assert resp.status_code == 200
    data = resp.json()
    assert "scenario_dataset_id" in data
    assert "impacted_habitations_count" in data

def test_ai_narrative(client):
    """
    Check if AI narrative generation works properly.
    """
    resp = client.get("/api/risk/habitations")
    habs = resp.json()["data"]
    if not habs:
        return
        
    hab_id = habs[0]["id"]
    resp = client.get(f"/api/ai/narrative/{hab_id}")
    assert resp.status_code == 200
    data = resp.json()
    assert data["methodology"] == "AI-ASSISTED"
    assert "narrative" in data

def test_end_to_end_sih26191_pipeline(client):
    """
    Phase 21 - The ultimate end-to-end integration test demonstrating the full SIH26191 pipeline.
    """
    # 1. Seed dataset
    resp = client.post("/api/datasets/seed-demo")
    assert resp.status_code == 200
    dataset_id = resp.json()["dataset_id"]
    
    # 2. Verify habitations
    resp = client.get("/api/risk/habitations")
    assert resp.status_code == 200
    habs = resp.json()["data"]
    assert len(habs) > 0
    hab_id = habs[0]["id"]
    
    # 3. Verify risk & vulnerability are calculated
    resp = client.get(f"/api/risk/habitations/{hab_id}")
    assert resp.status_code == 200
    hab_detail = resp.json()
    assert len(hab_detail["risk_assessments"]) > 0
    risk = hab_detail["risk_assessments"][0]
    assert "data_quality" in risk
    assert "methodology_name" in risk["contributing_factors"]
    
    resp = client.get("/api/vulnerability/habitations")
    assert resp.status_code == 200
    vulns = resp.json()["data"]
    assert len(vulns) > 0
    
    # 4. Verify Red Zone classification
    resp = client.get("/api/red-zones")
    assert resp.status_code == 200
    red_zones = resp.json()["data"]
    assert len(red_zones) > 0
    
    # 5. Verify Relocation Recommendations & Allocations
    resp = client.get("/api/relocation/summary")
    assert resp.status_code == 200
    reloc = resp.json()
    assert reloc["recommendations_generated"] > 0
    
    # 6. Create what-if scenario (disable a site)
    scenario_payload = {
        "disabled_site_ids": [1], # Disable the first site
        "added_hazards": []
    }
    resp = client.post(f"/api/scenarios/evaluate/{dataset_id}", json=scenario_payload)
    assert resp.status_code == 200
    scenario_result = resp.json()
    assert "impacted_habitations" in scenario_result
    
    # 7. Apply a field observation to baseline
    obs_payload = {
        "target_type": "SITE",
        "target_id": 1,
        "observation_type": "SITE_INACCESSIBLE",
        "details": {"reason": "Road blocked by landslide"},
        "source": "Field App"
    }
    resp = client.post(f"/api/field/observations/{dataset_id}", json=obs_payload)
    assert resp.status_code == 200
    
    # 8. Record Authority Decision
    dec_payload = {
        "habitation_id": hab_id,
        "recommended_site_id": 2,
        "status": "ACCEPTED",
        "actor": "District Magistrate",
        "rationale": "Proceeding with alternative site due to landslide"
    }
    resp = client.post(f"/api/field/decisions/{dataset_id}", json=dec_payload)
    assert resp.status_code == 200
    
    # 9. Verify AI Narrative
    resp = client.get(f"/api/ai/narrative/{hab_id}")
    assert resp.status_code == 200
    ai_data = resp.json()
    assert ai_data["methodology"] == "AI-ASSISTED"
    assert "narrative" in ai_data
