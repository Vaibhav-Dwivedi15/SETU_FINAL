"""
End-to-end check for POST /ingest, run against the real FastAPI app
in-process (no need for uvicorn to be running separately).

Sends one emergency packet, then a termination packet closing it, and
confirms via direct DB queries that a RawPacket + Incident actually got
created and closed -- not just that the endpoint returned 200.

Run with: python debug_test4.py
"""

from datetime import datetime, timezone
from fastapi.testclient import TestClient

from app.main import app
from app.db.base import SessionLocal
from app.models.packet import RawPacket
from app.models.incident import Incident, IncidentStatus

client = TestClient(app)

now = datetime.now(timezone.utc).isoformat()

emergency_packet = {
    "packet_id": "debug-p1",
    "sender_id": "debug-device-001",
    "type": "emergency",
    "timestamp": now,
    "nonce": "debug-nonce-1",
    "ttl": 5,
    "hop_count": 0,
    "protocol_version": 1,
    "signature": "debug-sig-1",
    "emergency_id": "debug-e1",
    "latitude": 28.6139,
    "longitude": 77.2090,
    "message": "Debug test -- trapped",
    "priority": "high",
    "incident_type": "fire",
}

termination_packet = {
    "packet_id": "debug-p2",
    "sender_id": "debug-device-001",
    "type": "termination",
    "timestamp": now,
    "nonce": "debug-nonce-2",
    "ttl": 5,
    "hop_count": 0,
    "protocol_version": 1,
    "signature": "debug-sig-2",
    "emergency_id": "debug-e1",
    "responder_id": "debug-responder-1",
}

print("--- POST /ingest (emergency) ---")
resp1 = client.post("/ingest", json={"packets": [emergency_packet]})
print(resp1.status_code, resp1.json())

print("\n--- POST /ingest (termination) ---")
resp2 = client.post("/ingest", json={"packets": [termination_packet]})
print(resp2.status_code, resp2.json())

print("\n--- DB verification ---")
db = SessionLocal()
try:
    raw = db.query(RawPacket).filter(RawPacket.packet_id == "debug-p1").first()
    print("RawPacket stored:", raw is not None)
    if raw:
        print("  type:", raw.type, "| emergency_id:", raw.emergency_id, "| incident_id:", raw.incident_id)

    if raw and raw.incident_id:
        incident = db.query(Incident).filter(Incident.id == raw.incident_id).first()
        print("Incident found:", incident is not None)
        if incident:
            print("  status:", incident.status, "| incident_type:", incident.incident_type)
            print("  PASS -- expected CLOSED" if incident.status == IncidentStatus.CLOSED else "  FAIL -- expected CLOSED after termination")
finally:
    db.close()