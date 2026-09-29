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
    
    recalculate_all_risks(db, dataset.id)
    
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
