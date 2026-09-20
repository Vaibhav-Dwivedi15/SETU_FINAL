from datetime import datetime, timezone
from app.db.base import SessionLocal
from app.models.incident import Incident, IncidentStatus
from app.schemas.packet import PacketIn
from app.services.deduplication_service import find_matching_incident

db = SessionLocal()

# Create a fresh test incident every time this script runs
test_incident = Incident(
    incident_type="fire",
    latitude=28.6139,
    longitude=77.2090,
    status=IncidentStatus.OPEN,
)
db.add(test_incident)
db.commit()
db.refresh(test_incident)
print("Created incident id:", test_incident.id)

nearby_packet = PacketIn(
    packet_version="1.0", packet_id="p200", sender_id="dev2", nonce="n200",
    timestamp=1234567890, packet_type="SOS",
    latitude=28.6140, longitude=77.2091,
    incident_type="fire", message="fire spreading",
    ttl=5, hop_count=1, signature="sig200"
)
match = find_matching_incident(db, nearby_packet)
print("Nearby match:", match.id if match else None, "-- should match", test_incident.id)

far_packet = PacketIn(
    packet_version="1.0", packet_id="p201", sender_id="dev3", nonce="n201",
    timestamp=1234567890, packet_type="SOS",
    latitude=28.7000, longitude=77.3000,
    incident_type="fire", message="different fire",
    ttl=5, hop_count=1, signature="sig201"
)
no_match = find_matching_incident(db, far_packet)
print("Far match:", no_match.id if no_match else None, "-- should be None")

db.close()