from app.schemas.packet import PacketIn, PacketBatchIn, PacketType

emergency = PacketIn(
    packet_id="p1", sender_id="dev1", type="emergency",
    timestamp="2026-08-01T12:00:00.000Z", nonce="n1",
    ttl=5, hop_count=1, protocol_version=1, signature="sig1",
    emergency_id="e1", latitude=28.6, longitude=77.2,
    incident_type="fire", message="fire!", priority="high",
)
print(emergency.type)

term = PacketIn(
    packet_id="p2", sender_id="dev1", type="termination",
    timestamp="2026-08-01T12:05:00.000Z", nonce="n2",
    ttl=5, hop_count=1, protocol_version=1, signature="sig2",
    emergency_id="e1", responder_id="resp-1",
)
print(term.type, term.emergency_id)

batch = PacketBatchIn(packets=[emergency, term])
print(len(batch.packets))