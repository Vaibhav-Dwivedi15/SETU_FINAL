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
    
def test_relocation_recommendations(client):
    """
    Check that recommendations are returned for the seeded data.
    """
    resp = client.get("/api/relocation/summary")
    assert resp.status_code == 200

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
