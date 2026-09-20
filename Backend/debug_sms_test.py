"""
Same as debug_test5.py, but broadcasts to multiple emergency contacts
at once -- proves notify_emergency_contacts() correctly loops through
every contact, not just the first one.

Every value that needs to be unique per run (sender_id, packet
identifiers, and location) is auto-generated below. To add or remove
people, just edit TEAM_NUMBERS and rerun -- nothing else needs to
change.

Run with: python debug_sms_test.py
"""

import random
import uuid
from datetime import datetime, timezone
from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)

# Add up to 5 numbers here -- yours plus your teammates'. 10-digit,
# no +91, matches how _to_e164() expects them. Just edit this list and
# rerun -- everything else below regenerates itself automatically.
TEAM_NUMBERS = [
    "6307260717",   # Ayush
    "7839352213",   # Vaibhav
    "8604990498",   # Sudheer
    "8853732303",   # Shaurya
]

# --- Everything below is auto-generated, no need to touch it ---

run_id = uuid.uuid4().hex[:10]

# Jitters the test location a random amount (0.01-1.0 degrees, in a
# random direction) away from central Delhi. 0.01 degrees is already
# ~1.1km -- comfortably past the 150m dedup radius -- so every run
# lands as a genuinely NEW incident instead of merging into a previous
# test run and silently skipping the SMS.
base_lat, base_lon = 28.6139, 77.2090
lat_jitter = random.choice([-1, 1]) * random.uniform(0.01, 1.0)
lon_jitter = random.choice([-1, 1]) * random.uniform(0.01, 1.0)

profile = {
    "sender_id": f"debug-sms-team-{run_id}",
    "name": "SETU Team Test",
    "age": 21,
    "gender": "male",
    "medical_history": "none",
    "emergency_contacts": TEAM_NUMBERS,
}

print(f"--- POST /register (run_id={run_id}) ---")
resp0 = client.post("/register", json=profile)
print(resp0.status_code, resp0.json())
if resp0.status_code not in (200, 409):
    raise SystemExit("Registration failed unexpectedly, stopping.")

now = datetime.now(timezone.utc).isoformat()

emergency_packet = {
    "packet_id": f"debug-sms-team-p-{run_id}",
    "sender_id": f"debug-sms-team-{run_id}",
    "type": "emergency",
    "timestamp": now,
    "nonce": f"debug-sms-team-nonce-{run_id}",
    "ttl": 5,
    "hop_count": 0,
    "protocol_version": 1,
    "signature": f"debug-sig-team-{run_id}",
    "emergency_id": f"debug-sms-team-e-{run_id}",
    "latitude": base_lat + lat_jitter,
    "longitude": base_lon + lon_jitter,
    "message": "SETU team SMS test -- please ignore",
    "priority": "high",
    "incident_type": "fire",
}

print("\n--- POST /ingest (emergency, should trigger SMS to all contacts) ---")
resp1 = client.post("/ingest", json={"packets": [emergency_packet]})
print(resp1.status_code, resp1.json())

print(f"\n--- Check every phone in TEAM_NUMBERS now. (run_id={run_id}) ---")