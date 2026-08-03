from app.db.base import SessionLocal
from app.schemas.packet import PacketIn
from app.models.packet import RawPacket, PacketStatus
from app.models.incident import Incident, IncidentStatus
from app.services.incident_service import handle_sos_packet, close_incident_by_packet_id

db = SessionLocal()

packet_a = PacketIn(
    packet_version="1.0", packet_id="svc-test-a3", sender_id="dev-a", nonce="n-a3",
    timestamp=1234567890, packet_type="SOS",
    latitude=28.6139, longitude=77.2090,
    incident_type="fire", message="first report",
    ttl=5, hop_count=1, signature="sig-a3"
)
raw_a = RawPacket(
    packet_version=packet_a.packet_version, packet_id=packet_a.packet_id,
    sender_id=packet_a.sender_id, nonce=packet_a.nonce, timestamp=packet_a.timestamp,
    packet_type=packet_a.packet_type.value,
    latitude=packet_a.latitude, longitude=packet_a.longitude,
    incident_type=packet_a.incident_type.value, message=packet_a.message,
    ttl=packet_a.ttl, hop_count=packet_a.hop_count, signature=packet_a.signature,
    status=PacketStatus.VALIDATED,
)
db.add(raw_a)
db.commit()

incident_1 = handle_sos_packet(db, packet_a)
print("Incident 1 id:", incident_1.id)

db.refresh(raw_a)
print("raw_a.incident_id:", raw_a.incident_id)
print("Link correct:", raw_a.incident_id == incident_1.id)

packet_b = PacketIn(
    packet_version="1.0", packet_id="svc-test-b3", sender_id="dev-b", nonce="n-b3",
    timestamp=1234567890, packet_type="SOS",
    latitude=28.6140, longitude=77.2091,
    incident_type="fire", message="second report",
    ttl=5, hop_count=1, signature="sig-b3"
)
raw_b = RawPacket(
    packet_version=packet_b.packet_version, packet_id=packet_b.packet_id,
    sender_id=packet_b.sender_id, nonce=packet_b.nonce, timestamp=packet_b.timestamp,
    packet_type=packet_b.packet_type.value,
    latitude=packet_b.latitude, longitude=packet_b.longitude,
    incident_type=packet_b.incident_type.value, message=packet_b.message,
    ttl=packet_b.ttl, hop_count=packet_b.hop_count, signature=packet_b.signature,
    status=PacketStatus.VALIDATED,
)
db.add(raw_b)
db.commit()

incident_2 = handle_sos_packet(db, packet_b)
print("Incident 2 id:", incident_2.id, "-- should match Incident 1's id:", incident_1.id)

closed = close_incident_by_packet_id(db, "svc-test-a3")
print("Closed incident id:", closed.id if closed else None, "-- should match", incident_1.id)
print("Status now:", closed.status if closed else None, "-- should be CLOSED")

closed_again = close_incident_by_packet_id(db, "svc-test-a3")
print("Second close attempt:", closed_again, "-- should be None")

unknown = close_incident_by_packet_id(db, "totally-fake-id")
print("Unknown packet_id result:", unknown, "-- should be None")

db.close()