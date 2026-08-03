import logging
logging.basicConfig(level=logging.INFO)

import random

from app.db.base import SessionLocal
from app.schemas.packet import PacketIn
from app.models.packet import RawPacket, PacketStatus
from app.models.user_profile import UserProfile
from app.services.incident_service import handle_sos_packet

db = SessionLocal()

unique_id = random.randint(10000, 99999)
sender_id = f"dev-sms-test-{unique_id}"
packet_id = f"sms-test-{unique_id}"

profile = db.query(UserProfile).filter(UserProfile.sender_id == sender_id).first()
if not profile:
    profile = UserProfile(
        sender_id=sender_id,
        name="Priya Sharma",
        emergency_contacts=["+919876511111", "+919876522222"],
    )
    db.add(profile)
    db.commit()

packet = PacketIn(
    packet_version="1.0",
    packet_id=packet_id,
    sender_id=sender_id,
    nonce=f"n-{unique_id}",
    timestamp=1234567890,
    packet_type="SOS",
    latitude=round(random.uniform(10, 30), 4),
    longitude=round(random.uniform(70, 90), 4),
    incident_type="flood",
    message="water rising fast",
    ttl=5,
    hop_count=1,
    signature=f"sig-{unique_id}",
)

raw = RawPacket(
    packet_version=packet.packet_version, packet_id=packet.packet_id,
    sender_id=packet.sender_id, nonce=packet.nonce, timestamp=packet.timestamp,
    packet_type=packet.packet_type.value,
    latitude=packet.latitude, longitude=packet.longitude,
    incident_type=packet.incident_type.value, message=packet.message,
    ttl=packet.ttl, hop_count=packet.hop_count, signature=packet.signature,
    status=PacketStatus.VALIDATED,
)

existing_raw = db.query(RawPacket).filter(RawPacket.packet_id == packet.packet_id).first()
if not existing_raw:
    db.add(raw)
    db.commit()

print(f"--- Creating NEW incident at ({packet.latitude}, {packet.longitude}) — should trigger SMS stub log ---")
incident_1 = handle_sos_packet(db, packet)
print("Incident id:", incident_1.id)

db.close()