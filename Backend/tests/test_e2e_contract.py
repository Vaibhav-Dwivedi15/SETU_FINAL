"""
Block 2 -- deterministic end-to-end contract test.

  Flutter-produced wire packet  (docs/backend/contract/dart_wire/*.json, written
        |                         by setu_app/test/cross_language_signature_test.dart
        v                         from the real SigningService + packet models)
  backend validation -> signature verification -> dedup identity -> incident
        -> AI triage + dedup decision -> response body
        v
  mobile interpretation         (the REAL Dart BackendService.classifyIngestResponse,
                                 fed the response bodies recorded here in
                                 docs/backend/contract/ingest_scenarios.json by
                                 setu_app/test/backend_contract_test.dart)

For every scenario the test asserts the backend's answer, the database truth
and the state a mobile client will derive are the SAME state. Regenerate the
scenario file deliberately: UPDATE_CONTRACT_FIXTURES=1.

Time is frozen (the Dart fixtures carry a fixed 2026-09-24 timestamp) by patching
ingest_service.age_seconds; request-signing freshness uses the real clock.
"""

import copy
import json
import os
import pathlib
from datetime import datetime, timezone
from types import SimpleNamespace

import pytest
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey

from app.core.config import settings
from app.models.incident import Incident, IncidentStatus
from app.models.packet import RawPacket
from app.services.signature_service import build_signed_payload
from tests.signing_helpers import pubkey_hex, register_profile, signed_json_post, signed_nearby, signed_voice
from tests.test_ingest import _pubkey_hex_for, _sign_packet, client, make_emergency  # noqa: F401
from tests.test_ingest_contract import db_session
from tests.test_request_auth import WAV, new_key

CONTRACT = pathlib.Path(__file__).resolve().parents[2] / "docs/backend/contract"
WIRE = CONTRACT / "dart_wire"
SCENARIOS = CONTRACT / "ingest_scenarios.json"
FIXED_NOW = datetime(2026, 9, 24, 10, 30, 25, tzinfo=timezone.utc)
SEED = bytes(range(32))
API_KEY = "test-responder-api-key"

# What a mobile client derives from each backend state (Dart UploadOutcome) and whether it ACKs.
MOBILE = {"ACCEPTED": ("accepted", True), "DUPLICATE": ("duplicate", True), "REJECTED": ("rejected", False), "FAILED": ("failed", False)}


def wire(name):
    return json.loads((WIRE / f"{name}.json").read_text(encoding="utf-8"))


@pytest.fixture()
def env(client, monkeypatch):
    import app.services.ingest_service as svc
    monkeypatch.setattr(svc, "age_seconds", lambda sent_at, now=None: (FIXED_NOW - sent_at).total_seconds())
    original = settings.responder_api_key
    settings.responder_api_key = API_KEY
    recorded = []

    def post(scenario, *packets, expect_state=None, now=None):
        if now is not None:
            monkeypatch.setattr(svc, "age_seconds", lambda sent_at, n=None: (now - sent_at).total_seconds())
        resp = client.post("/ingest", json={"packets": list(packets)})
        assert resp.status_code == 200  # HTTP success != acceptance
        body = resp.json()
        assert len(body["accepted"]) + len(body["duplicates"]) + len(body["rejected"]) + len(body["failed"]) == len(packets)
        entry = next(e for bucket in ("accepted", "duplicates", "rejected", "failed") for e in body[bucket] if e["packet_id"] == packets[-1]["packet_id"])
        if expect_state:
            assert entry["status"] == expect_state, (scenario, entry)
        recorded.append({
            "scenario": scenario, "packet_id": packets[-1]["packet_id"], "backend_state": entry["status"],
            "mobile_outcome": MOBILE[entry["status"]][0], "mobile_acks": MOBILE[entry["status"]][1], "response_body": json.dumps(body, sort_keys=True),
        })
        return entry, body

    yield SimpleNamespace(client=client, post=post, recorded=recorded, monkeypatch=monkeypatch, headers={"x-api-key": API_KEY})
    settings.responder_api_key = original
    if os.environ.get("UPDATE_CONTRACT_FIXTURES"):
        SCENARIOS.write_text(json.dumps(recorded, indent=2, sort_keys=True) + "\n")
    else:
        assert json.loads(SCENARIOS.read_text()) == recorded, "ingest_scenarios.json drifted; regenerate deliberately"


def stored(packet):
    return db_session().query(RawPacket).filter(RawPacket.sender_id == packet["sender_id"], RawPacket.packet_id == packet["packet_id"]).count()


def resign(packet, **changes):
    key = Ed25519PrivateKey.from_private_bytes(SEED)
    packet = {**packet, **changes}
    ns = SimpleNamespace(**{k: packet.get(k) for k in ("packet_id", "sender_id", "type", "timestamp", "nonce", "emergency_id", "latitude", "longitude", "message", "priority", "responder_id")})
    packet["signature"] = key.sign(build_signed_payload(ns).encode()).hex()
    return packet


def test_full_contract_walk(env):
    client, dart = env.client, wire("emergency")
    incident_ids = {}

    # 1. accepted emergency (real Dart packet: unicode + pipe + quote in the message)
    entry, _ = env.post("1_accepted_emergency", dart, expect_state="ACCEPTED")
    assert stored(dart) == 1 and entry["dedup_decision"] == "NEW_INCIDENT"
    incident = db_session().query(Incident).one()
    assert incident.status == IncidentStatus.OPEN and incident.ai_priority is not None  # AI ran
    assert incident.sender_priority == "critical" and (incident.latitude, incident.longitude) == (25.4358011, 81.8463302)
    incident_ids["dart"] = entry["incident_id"]

    # 2. duplicate emergency: same packet again -> DUPLICATE (backend holds it), same incident
    entry, _ = env.post("2_duplicate_emergency", dart, expect_state="DUPLICATE")
    assert entry["incident_id"] == incident_ids["dart"] and stored(dart) == 1
    assert db_session().query(RawPacket).count() == 1

    # 2b. relayed copy (ttl/hop rewritten, unsigned fields) is the SAME packet
    relayed = wire("relay_rewrites_ttl_hop")
    entry, _ = env.post("2b_relayed_copy_is_duplicate", relayed, expect_state="DUPLICATE")

    # 3. rejected: every tampered variant Dart produced fails signature verification and is never stored
    for name in ("tamper_message", "tamper_latitude", "tamper_priority", "tamper_signature", "tamper_sender_id", "tamper_emergency_id", "tamper_timestamp", "tamper_nonce", "tamper_packet_id"):
        packet = wire(name)
        entry, _ = env.post(f"3_rejected_{name}", packet, expect_state="REJECTED")
        assert entry["code"] == "invalid_signature", name
    # nothing was stored or altered by any of them: still exactly the one genuine row, content intact
    row = db_session().query(RawPacket).one()
    assert (row.message, row.latitude, row.priority) == (dart["message"], dart["latitude"], dart["priority"])

    # 4. stale emergency (same genuine Dart packet, but "now" is 2 h later) is rejected, not stored
    other = wire("emergency_wholedeg")
    entry, _ = env.post("4_stale_emergency", other, expect_state="REJECTED", now=datetime(2026, 9, 24, 12, 45, tzinfo=timezone.utc))
    assert entry["code"] == "stale" and stored(other) == 0
    # ...and the same packet is accepted while fresh (frozen clock restored) -> nothing was poisoned by the rejection
    import app.services.ingest_service as svc
    entry, _ = env.post("4b_same_packet_when_fresh", other, expect_state="ACCEPTED", now=FIXED_NOW)
    assert stored(other) == 1

    # 5. packet-ID collision: an attacker key reuses the Dart packet_id; the genuine sender is unaffected
    attacker = Ed25519PrivateKey.generate()
    forged = {**wire("emergency"), "packet_id": "wholedeg-2", "sender_id": pubkey_hex(attacker), "message": "squat"}
    forged["signature"] = "00" * 64  # unsigned squat attempt
    env.post("5a_squat_invalid_signature", forged, expect_state="REJECTED")
    genuine = resign(wire("emergency_wholedeg"), packet_id="wholedeg-2", emergency_id="wholedeg-2", timestamp="2026-09-24T10:30:16.000Z", nonce="dddddddddddddddddddddddddddddddd")
    entry, _ = env.post("5b_genuine_after_collision", genuine, expect_state="ACCEPTED")
    assert stored(genuine) == 1

    # 6. voice request (signed) creates an incident attributed to the authenticated key
    import app.routers.voice as voice_router
    env.monkeypatch.setattr(voice_router, "transcription_available", lambda: True)
    env.monkeypatch.setattr(voice_router, "transcribe", lambda path: "Building collapse near the market, people under rubble")
    vkey = new_key()
    voice = signed_voice(client, vkey, WAV, lat="19.0760", lon="72.8777", priority="high")
    assert voice.status_code == 200, voice.text
    voice_body = voice.json()
    assert db_session().query(RawPacket).filter(RawPacket.packet_id == voice_body["packet_id"]).one().sender_id == pubkey_hex(vkey)

    # 7. nearby alert: a registered device near Prayagraj sees the Dart incident, minimal fields only
    viewer = new_key()
    assert register_profile(client, viewer, name="Viewer").status_code == 200
    nearby = signed_nearby(client, viewer, {"lat": "25.4358", "lon": "81.8463", "radius_km": "5"})
    assert nearby.status_code == 200
    rows = nearby.json()
    assert [r["incident_id"] for r in rows] == [incident_ids["dart"]]
    assert "sender_id" not in rows[0] and "latitude" not in rows[0]

    # 8. responder (community) response is attributed to the signed key and visible to the dashboard
    respond = signed_json_post(client, viewer, f"/alerts/{incident_ids['dart']}/respond", {"sender_id": pubkey_hex(viewer), "response_type": "CAN_HELP"})
    assert respond.status_code == 200
    responses = client.get(f"/incidents/{incident_ids['dart']}/responses", headers=env.headers).json()
    assert [r["sender_id"] for r in responses] == [pubkey_hex(viewer)]

    # 9. dashboard view agrees with everything above
    listed = {i["id"]: i for i in client.get("/incidents", headers=env.headers).json()}
    assert listed[incident_ids["dart"]]["status"] == "OPEN"
    assert listed[incident_ids["dart"]]["sender_priority"] == "critical"
    assert listed[incident_ids["dart"]]["display_priority"] in ("Critical", "High", "Medium", "Low")
    assert listed[incident_ids["dart"]]["report_count"] >= 1

    # 10. resolution: an unauthorised termination is REJECTED; once the key is a registered responder, a
    #     Dart-key-signed termination for the incident's emergency_id closes it and everything agrees.
    term = resign({"packet_id": "term-e2e", "sender_id": dart["sender_id"], "type": "termination", "timestamp": "2026-09-24T10:30:20.000Z",
                   "nonce": "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee", "ttl": 5, "hop_count": 0, "protocol_version": 1,
                   "emergency_id": dart["emergency_id"], "responder_id": "badge-7"})
    entry, _ = env.post("10a_termination_unauthorized", term, expect_state="REJECTED")
    assert entry["code"] == "unauthorized_responder" and stored(term) == 0
    assert client.post("/responders", json={"public_key": dart["sender_id"], "name": "R"}, headers={"x-api-key": "test-admin-api-key"}).status_code == 200
    entry, _ = env.post("10b_termination_authorized", term, expect_state="ACCEPTED")
    assert entry["closed_incident_id"] == incident_ids["dart"]
    incident = db_session().query(Incident).filter(Incident.id == incident_ids["dart"]).one()
    assert incident.status == IncidentStatus.CLOSED and incident.closed_at is not None
    listed = {i["id"]: i for i in client.get("/incidents", headers=env.headers).json()}
    assert listed[incident_ids["dart"]]["status"] == "CLOSED"
    assert signed_nearby(client, viewer, {"lat": "25.4358", "lon": "81.8463", "radius_km": "5"}).json() == []
    entry, _ = env.post("10c_termination_retry_is_duplicate", term, expect_state="DUPLICATE")

    # 11. mesh-only packet types are never accepted (no ACK/alert upload loop)
    for name in ("ack", "alert"):
        packet = wire(name)
        entry, _ = env.post(f"11_{name}_never_accepted", packet, expect_state="REJECTED")
        assert entry["code"] == "unsupported_type" and stored(packet) == 0

    # The mobile interpretation table is total and consistent with the states seen.
    assert {r["backend_state"] for r in env.recorded} == {"ACCEPTED", "DUPLICATE", "REJECTED"}
