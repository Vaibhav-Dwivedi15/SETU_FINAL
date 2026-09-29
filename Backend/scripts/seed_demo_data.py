import os
import sys

# Add backend directory to Python path
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from app.db.base import SessionLocal
from app.models.gis_models import Dataset, Habitation, HazardLayer, RelocationSite
from app.services.gis_service import get_bounding_box
from app.services.capacity_service import calculate_capacity
from app.services.risk_service import recalculate_all_risks
from app.services.vulnerability_service import recalculate_all_vulnerabilities
from app.services.relocation_service import recalculate_all_recommendations

def seed_data():
    db = SessionLocal()
    
    # 1. Create Demo Dataset
    from app.db.init_db import init_db
    init_db()
    existing_dataset = db.query(Dataset).filter(Dataset.name == "SETU Demo Dataset").first()
    if existing_dataset:
        print("Demo dataset already exists, deleting old data...")
        dataset_id = existing_dataset.id
        db.query(Habitation).filter(Habitation.dataset_id == dataset_id).delete()
        db.query(HazardLayer).filter(HazardLayer.dataset_id == dataset_id).delete()
        db.query(RelocationSite).filter(RelocationSite.dataset_id == dataset_id).delete()
        # cascades would handle risk, vulnerability, etc if configured, but let's be explicit just in case
        db.query(Dataset).filter(Dataset.id == dataset_id).delete()
        db.commit()

    print("Creating new demo dataset...")
    dataset = Dataset(
        name="SETU Demo Dataset",
        is_demo=True,
        source="SETU Internal Demo Seeder"
    )
    db.add(dataset)
    db.commit()
    db.refresh(dataset)
    dataset_id = dataset.id
    
    # 2. Create Habitations (20-50 demo habitations)
    # Let's create around 20 near Prayagraj (25.4358, 81.8463)
    base_lat = 25.4358
    base_lon = 81.8463
    
    habitations = []
    for i in range(25):
        # spread them out a bit
        lat = base_lat + (i * 0.01) - 0.1
        lon = base_lon + ((i % 5) * 0.01) - 0.02
        pop = 500 + (i * 150)
        
        hab = Habitation(
            name=f"Demo Village {i+1}",
            district="Prayagraj",
            state="Uttar Pradesh",
            population=pop,
            latitude=lat,
            longitude=lon,
            dataset_id=dataset_id
        )
        habitations.append(hab)
    
    db.add_all(habitations)
    db.commit()

    # 3. Create Hazard Layers
    # Create a flood polygon that intersects some habitations
    flood_polygon = {
        "type": "Polygon",
        "coordinates": [[
            [base_lon - 0.05, base_lat - 0.05],
            [base_lon + 0.05, base_lat - 0.05],
            [base_lon + 0.05, base_lat + 0.05],
            [base_lon - 0.05, base_lat + 0.05],
            [base_lon - 0.05, base_lat - 0.05]
        ]]
    }
    
    min_lat, max_lat, min_lon, max_lon = get_bounding_box(flood_polygon)
    
    hazard1 = HazardLayer(
        hazard_type="flood",
        severity="critical",
        geometry=flood_polygon,
        min_lat=min_lat,
        max_lat=max_lat,
        min_lon=min_lon,
        max_lon=max_lon,
        source="Demo Flood API",
        dataset_id=dataset_id
    )
    
    # Another hazard - landslide
    landslide_polygon = {
        "type": "Polygon",
        "coordinates": [[
            [base_lon + 0.01, base_lat + 0.01],
            [base_lon + 0.1, base_lat + 0.01],
            [base_lon + 0.1, base_lat + 0.1],
            [base_lon + 0.01, base_lat + 0.1],
            [base_lon + 0.01, base_lat + 0.01]
        ]]
    }
    min_lat2, max_lat2, min_lon2, max_lon2 = get_bounding_box(landslide_polygon)
    
    hazard2 = HazardLayer(
        hazard_type="landslide",
        severity="high",
        geometry=landslide_polygon,
        min_lat=min_lat2,
        max_lat=max_lat2,
        min_lon=min_lon2,
        max_lon=max_lon2,
        source="Demo Landslide API",
        dataset_id=dataset_id
    )
    
    db.add_all([hazard1, hazard2])
    db.commit()

    # 4. Create Relocation Sites (5-10)
    sites = []
    for i in range(8):
        lat = base_lat + (i * 0.02) - 0.05
        lon = base_lon + (i * 0.02) - 0.05
        usable_area = 10000.0 + (i * 5000)
        
        cap = calculate_capacity(usable_area, occupancy=i*100)
        
        site = RelocationSite(
            name=f"Safe Zone {i+1}",
            district="Prayagraj",
            state="Uttar Pradesh",
            latitude=lat,
            longitude=lon,
            usable_area_sqm=usable_area,
            infrastructure={"road_access": True, "water": True, "electricity": (i % 2 == 0)},
            services={"hospital": (i % 3 == 0), "school": True},
            current_occupancy=cap["current_occupancy"],
            estimated_capacity=cap["estimated_capacity"],
            remaining_capacity=cap["remaining_capacity"],
            source="Demo Sites Database",
            dataset_id=dataset_id
        )
        sites.append(site)
        
    db.add_all(sites)
    db.commit()

    print("Data inserted. Running Risk, Vulnerability and Relocation engines...")

    # 5. Calculate engines
    recalculate_all_vulnerabilities(db, dataset_id)
    recalculate_all_risks(db, dataset_id)
    recalculate_all_recommendations(db, dataset_id)

    print("Demo dataset seeded successfully!")

if __name__ == "__main__":
    seed_data()
