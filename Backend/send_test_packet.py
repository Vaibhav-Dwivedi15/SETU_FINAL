"""
One-off end-to-end smoke test: builds a REAL, genuinely-signed emergency
packet (signature verification is no longer a stub, so a fake signature
gets rejected at /ingest), POSTs it to your running server, then queries
the DB directly to confirm the AI fields actually landed on the Incident
row -- not just that the request returned 200.

Run once, with your server already running in another terminal:
    python send_test_packet.py
    python send_test_packet.py http://your-render-url.onrender.com

Defaults to http://localhost:8000 if no URL is given.
"""

import sys
import uuid
from datetime import datetime, timezone

import requests
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey

from app.db.base import SessionLocal
from app.models.incident import Incident
from app.services.signature_service import build_signed_payload

BASE_URL = sys.argv[1] if len(sys.argv) > 1 else "http://localhost:8000"


def make_signed_emergency_packet():
    private_key = Ed25519PrivateKey.generate()
    sender_id = private_key.public_key().public_bytes_raw().hex()

    packet = {
        "packet_id": f"test-{uuid.uuid4().hex[:8]}",
        "sender_id": sender_id,
        "type": "emergency",
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "nonce": uuid.uuid4().hex,
        "ttl": 5,
        "hop_count": 0,
        "protocol_version": 1,
        "emergency_id": f"e-test-{uuid.uuid4().hex[:8]}",
        "latitude": 28.6139,
        "longitude": 77.2090,
        "message": "Fire in my building, need help fast",
        "priority": "high",
    }

    class _P:
        pass
    p = _P()
    for k, v in packet.items():
        setattr(p, k, v)
    p.responder_id = None

    payload = build_signed_payload(p)
    packet["signature"] = private_key.sign(payload.encode("utf-8")).hex()
    return packet


def main():
    packet = make_signed_emergency_packet()
    print(f"POSTing signed emergency packet to {BASE_URL}/ingest ...")
    resp = requests.post(f"{BASE_URL}/ingest", json={"packets": [packet]})
    resp.raise_for_status()
    result = resp.json()
    print("Response:", result)

    if not result["accepted"]:
        print("FAILED: packet was rejected, see 'rejected' above -- signature/TTL/dup check failed.")
        return

    incident_id = result["accepted"][0]["incident_id"]
    print(f"Accepted -- incident_id={incident_id}. Querying DB directly for AI fields...")

    db = SessionLocal()
    try:
        incident = db.query(Incident).filter(Incident.id == incident_id).first()
        if not incident:
            print("FAILED: incident row not found in DB.")
            return
        print("sender_priority          :", incident.sender_priority)
        print("ai_incident_type          :", incident.ai_incident_type)
        print("ai_incident_confidence    :", incident.ai_incident_confidence)
        print("ai_incident_explanation   :", incident.ai_incident_explanation)
        print("ai_urgency                :", incident.ai_urgency)
        print("ai_urgency_confidence     :", incident.ai_urgency_confidence)
        print("ai_urgency_explanation    :", incident.ai_urgency_explanation)
        print("ai_priority               :", incident.ai_priority)

        if incident.ai_incident_type is None:
            print("\nWARNING: ai_incident_type is None -- AI analysis likely failed silently")
            print("(check server logs for 'AI analysis failed' or 'setu_ai_service import failed').")
        else:
            print("\nSUCCESS: AI fields populated end-to-end.")
    finally:
        db.close()


if __name__ == "__main__":
    main()
