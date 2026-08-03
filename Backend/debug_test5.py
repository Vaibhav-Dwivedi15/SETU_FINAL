"""
End-to-end check that /ingest actually triggers a real SMS via the
SMS Gateway for Android integration -- not just that the raw gateway
API works (debug_test5 proves the full path: register a profile with
an emergency contact -> POST an emergency packet -> confirm the SMS
fires through incident_service.handle_sos_packet()).

Runs against the real app + real DB (whatever DATABASE_URL is set to
in .env, currently Neon) and the real SMS Gateway credentials -- this
WILL send a real SMS to the phone number below if everything's wired
correctly. Not a pytest test; a one-off manual check, same pattern as
debug_test4.py.

Run with: python -m debug_test5
"""

from datetime import datetime, timezone
from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)

# CHANGE THIS to your own real number before running, so the SMS lands
# on a phone you can actually check.
MY_PHONE_NUMBER = "6307260717"

profile = {
    "sender_id": "debug-sms-test-device",
    "name": "Ayush (SMS Test)",
    "age": 21,
    "gender": "male",
    "medical_history": "none",
    "emergency_contacts": [MY_PHONE_NUMBER],
}

print("--- POST /register ---")
resp0 = client.post("/register", json=profile)
print(resp0.status_code, resp0.json())
if resp0.status_code not in (200, 409):
    raise SystemExit("Registration failed unexpectedly, stopping.")

now = datetime.now(timezone.utc).isoformat()

emergency_packet = {
    "packet_id": "debug-sms-p1",
    "sender_id": "debug-sms-test-device",
    "type": "emergency",
    "timestamp": now,
    "nonce": "debug-sms-nonce-1",
    "ttl": 5,
    "hop_count": 0,
    "protocol_version": 1,
    "signature": "debug-sig-1",
    "emergency_id": "debug-sms-e1",
    "latitude": 28.6139,
    "longitude": 77.2090,
    "message": "SMS integration test -- please ignore",
    "priority": "high",
    "incident_type": "fire",
}

print("\n--- POST /ingest (emergency, should trigger SMS) ---")
resp1 = client.post("/ingest", json={"packets": [emergency_packet]})
print(resp1.status_code, resp1.json())

print("\n--- Check your phone for the SMS now. ---")
print("If nothing arrives, check the server logs above this output for")
print("any '[SMS]' log lines -- they'll say exactly what happened")
print("(queued successfully, credentials missing, or a gateway error).")