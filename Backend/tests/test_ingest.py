"""
Integration tests for POST /ingest.

Runs against an isolated in-memory SQLite database (via dependency
override of get_db) so these tests never touch the real dev Postgres
database and can run repeatably / in CI. Formalizes what debug_test4.py
checked manually.

Termination tests register a trusted responder by their Ed25519 PUBLIC
KEY (via POST /responders) before sending a termination packet.
Authorization is checked against packet.sender_id, NOT packet.
responder_id -- confirmed with Vaibhav (Mesh Lead): responder_id is
spoofable display metadata (e.g. a badge number), never used for auth.
Several tests below exist specifically to prove that fact holds on the
backend too.
"""

from datetime import datetime, timedelta, timezone
from types import SimpleNamespace

import pytest
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.main import app
from app.core.config import settings
from app.db.base import Base, get_db
from app.services.signature_service import build_signed_payload

TEST_API_KEY = "test-responder-api-key"

# Signature verification is real (Ed25519) as of Day 5 -- every packet
# built below must carry a genuine signature or it's rejected before
# authorization/dedup/anything else is ever checked. These helpers map a
# human-readable device name (e.g. "dev-1", "responder-device-1") to a
# real, consistently-reused Ed25519 keypair for the life of the test
# process, so `sender_id` in the JSON is always the actual hex pubkey
# signature_service.py expects -- never the friendly name itself.
_DEVICE_KEYS: dict[str, Ed25519PrivateKey] = {}


def _private_key_for(device_name: str) -> Ed25519PrivateKey:
    if device_name not in _DEVICE_KEYS:
        _DEVICE_KEYS[device_name] = Ed25519PrivateKey.generate()
    return _DEVICE_KEYS[device_name]


def _pubkey_hex_for(device_name: str) -> str:
    return _private_key_for(device_name).public_key().public_bytes_raw().hex()


def _sign_packet(packet: dict, device_name: str) -> str:
    """
    Build the exact signed payload (via the real
    signature_service.build_signed_payload -- same code path production
    uses, so these tests can't silently drift from it) and sign it with
    device_name's private key. packet["sender_id"] must already be the
    hex pubkey (see _pubkey_hex_for) by the time this is called.
    """
    payload_obj = SimpleNamespace(
        packet_id=packet["packet_id"],
        sender_id=packet["sender_id"],
        type=packet["type"],
        timestamp=packet["timestamp"],
        nonce=packet["nonce"],
        emergency_id=packet.get("emergency_id"),
        latitude=packet.get("latitude"),
        longitude=packet.get("longitude"),
        message=packet.get("message"),
        priority=packet.get("priority"),
        responder_id=packet.get("responder_id"),
    )
    payload = build_signed_payload(payload_obj)
    signature_bytes = _private_key_for(device_name).sign(payload.encode("utf-8"))
    return signature_bytes.hex()


@pytest.fixture()
def client():
    engine = create_engine(
        "sqlite:///:memory:",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    TestingSessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
    Base.metadata.create_all(bind=engine)

    def override_get_db():
        db = TestingSessionLocal()
        try:
            yield db
        finally:
            db.close()

    app.dependency_overrides[get_db] = override_get_db

    # Pin the responder API key to a known value for the duration of the
    # test, regardless of whatever is in the developer's local .env, so
    # these tests never depend on machine-specific config.
    original_api_key = settings.responder_api_key
    settings.responder_api_key = TEST_API_KEY

    test_client = TestClient(app)
    yield test_client

    settings.responder_api_key = original_api_key
    app.dependency_overrides.clear()
    Base.metadata.drop_all(bind=engine)


def register_responder(client, public_key="responder-device-1", name="Test Responder"):
    resp = client.post(
        "/responders",
        json={"public_key": public_key, "name": name},
        headers={"x-api-key": TEST_API_KEY},
    )
    assert resp.status_code == 200, resp.text
    return resp.json()


def make_emergency(packet_id="p1", emergency_id="e1", sender_id="dev-1",
                    timestamp=None, latitude=28.6139, longitude=77.2090,
                    incident_type="fire"):
    """
    sender_id is a friendly device name (e.g. "dev-1") -- resolved to a
    real Ed25519 hex pubkey via _pubkey_hex_for() and used as the actual
    sender_id in the wire packet, which is then genuinely signed. Pass
    the same name to register_responder() for termination tests that
    need this identity to also be an authorized responder.
    """
    real_sender_id = _pubkey_hex_for(sender_id)
    packet = {
        "packet_id": packet_id,
        "sender_id": real_sender_id,
        "type": "emergency",
        "timestamp": timestamp or datetime.now(timezone.utc).isoformat(),
        "nonce": f"nonce-{packet_id}",
        "ttl": 5,
        "hop_count": 0,
        "protocol_version": 1,
        "emergency_id": emergency_id,
        "latitude": latitude,
        "longitude": longitude,
        "message": "test emergency",
        "priority": "high",
        "incident_type": incident_type,
    }
    packet["signature"] = _sign_packet(packet, sender_id)
    return packet


def make_termination(packet_id="p2", emergency_id="e1", sender_id="responder-device-1",
                      timestamp=None, responder_id="badge-123"):
    """
    sender_id here is the RESPONDER's own device identity (the value
    checked against the registry) -- distinct from the citizen device
    (e.g. "dev-1") that reported the original emergency. responder_id is
    the cosmetic/display field, deliberately given an arbitrary value by
    default to prove it's never load-bearing for authorization.

    Like make_emergency, sender_id is a friendly name resolved to a real
    Ed25519 hex pubkey -- register that same name via register_responder()
    (using _pubkey_hex_for(name) as the public_key) for tests that need
    this sender authorized.
    """
    real_sender_id = _pubkey_hex_for(sender_id)
    packet = {
        "packet_id": packet_id,
        "sender_id": real_sender_id,
        "type": "termination",
        "timestamp": timestamp or datetime.now(timezone.utc).isoformat(),
        "nonce": f"nonce-{packet_id}",
        "ttl": 5,
        "hop_count": 0,
        "protocol_version": 1,
        "emergency_id": emergency_id,
        "responder_id": responder_id,
    }
    packet["signature"] = _sign_packet(packet, sender_id)
    return packet


def test_emergency_packet_creates_incident(client):
    resp = client.post("/ingest", json={"packets": [make_emergency()]})
    assert resp.status_code == 200
    body = resp.json()
    assert len(body["accepted"]) == 1
    assert body["rejected"] == []
    assert body["accepted"][0]["incident_id"] is not None


def test_termination_packet_closes_incident(client):
    register_responder(client, public_key=_pubkey_hex_for("responder-device-1"))
    client.post("/ingest", json={"packets": [make_emergency(packet_id="p1", emergency_id="e1")]})
    resp = client.post("/ingest", json={"packets": [make_termination(packet_id="p2", emergency_id="e1")]})
    assert resp.status_code == 200
    body = resp.json()
    assert body["accepted"][0]["closed_incident_id"] is not None


def test_termination_with_unknown_emergency_id_is_a_silent_noop(client):
    register_responder(client, public_key=_pubkey_hex_for("responder-device-1"))
    resp = client.post(
        "/ingest",
        json={"packets": [make_termination(packet_id="p2", emergency_id="does-not-exist")]},
    )
    assert resp.status_code == 200
    body = resp.json()
    assert body["accepted"][0]["closed_incident_id"] is None


def test_termination_from_unregistered_sender_rejected(client):
    # Deliberately skip register_responder() -- "responder-device-1" is unknown.
    resp = client.post(
        "/ingest",
        json={"packets": [make_termination(packet_id="p2", emergency_id="e1", sender_id="responder-device-1")]},
    )
    assert resp.status_code == 200
    body = resp.json()
    assert body["accepted"] == []
    assert body["rejected"][0]["reason"] == "unauthorized responder"


def test_termination_succeeds_even_when_responder_id_is_missing(client):
    """
    responder_id is cosmetic metadata, never checked for auth -- a
    termination from a genuinely registered sender_id must succeed even
    with no responder_id at all.
    """
    register_responder(client, public_key=_pubkey_hex_for("responder-device-1"))
    client.post("/ingest", json={"packets": [make_emergency(packet_id="p1", emergency_id="e1")]})
    packet = make_termination(packet_id="p2", emergency_id="e1", responder_id=None)
    resp = client.post("/ingest", json={"packets": [packet]})
    body = resp.json()
    assert body["accepted"][0]["closed_incident_id"] is not None


def test_termination_rejected_despite_convincing_responder_id_if_sender_unregistered(client):
    """
    The exact vulnerability Vaibhav flagged: a spoofed/convincing-looking
    responder_id (e.g. a fake badge number) must NOT grant authorization
    on its own. Only a registered sender_id does.
    """
    packet = make_termination(
        packet_id="p2",
        emergency_id="e1",
        sender_id="totally-unregistered-device",
        responder_id="official-looking-badge-007",
    )
    resp = client.post("/ingest", json={"packets": [packet]})
    body = resp.json()
    assert body["accepted"] == []
    assert body["rejected"][0]["reason"] == "unauthorized responder"


def test_duplicate_responder_registration_conflicts(client):
    register_responder(client, public_key="responder-device-1")
    resp = client.post(
        "/responders",
        json={"public_key": "responder-device-1", "name": "Duplicate"},
        headers={"x-api-key": TEST_API_KEY},
    )
    assert resp.status_code == 409


def test_responder_registration_requires_api_key(client):
    resp = client.post(
        "/responders",
        json={"public_key": "responder-device-1", "name": "No Key"},
    )
    assert resp.status_code in (401, 422)  # 422 if header is strictly required by FastAPI


def test_responder_keys_endpoint_lists_active_keys_only(client):
    register_responder(client, public_key="key-active")
    resp = client.get("/responders/keys")
    assert resp.status_code == 200
    assert resp.json() == {"responder_public_keys": ["key-active"]}


def test_responder_keys_endpoint_empty_when_none_registered(client):
    resp = client.get("/responders/keys")
    assert resp.status_code == 200
    assert resp.json() == {"responder_public_keys": []}


def test_responder_keys_endpoint_requires_no_auth(client):
    # No x-api-key header at all -- must still succeed, per the mesh contract.
    resp = client.get("/responders/keys")
    assert resp.status_code == 200


def test_duplicate_packet_id_rejected(client):
    packet = make_emergency(packet_id="dup-1", emergency_id="e-dup")
    client.post("/ingest", json={"packets": [packet]})
    resp = client.post("/ingest", json={"packets": [packet]})
    body = resp.json()
    assert body["accepted"] == []
    assert body["rejected"][0]["reason"] == "duplicate packet_id"


def test_expired_ttl_rejected(client):
    stale_timestamp = (datetime.now(timezone.utc) - timedelta(hours=2)).isoformat()
    packet = make_emergency(packet_id="stale-1", emergency_id="e-stale", timestamp=stale_timestamp)
    resp = client.post("/ingest", json={"packets": [packet]})
    body = resp.json()
    assert body["accepted"] == []
    assert body["rejected"][0]["reason"] == "TTL expired"


def test_nearby_same_type_reports_merge_into_one_incident(client):
    first = make_emergency(packet_id="m1", emergency_id="e-m1",
                            latitude=28.6139, longitude=77.2090, incident_type="fire")
    second = make_emergency(packet_id="m2", emergency_id="e-m2",
                             latitude=28.6140, longitude=77.2091, incident_type="fire")

    resp1 = client.post("/ingest", json={"packets": [first]})
    resp2 = client.post("/ingest", json={"packets": [second]})

    incident_id_1 = resp1.json()["accepted"][0]["incident_id"]
    incident_id_2 = resp2.json()["accepted"][0]["incident_id"]

    assert incident_id_1 == incident_id_2


def test_far_apart_reports_create_separate_incidents(client):
    first = make_emergency(packet_id="f1", emergency_id="e-f1",
                            latitude=28.6139, longitude=77.2090, incident_type="fire")
    second = make_emergency(packet_id="f2", emergency_id="e-f2",
                             latitude=19.0760, longitude=72.8777, incident_type="fire")

    resp1 = client.post("/ingest", json={"packets": [first]})
    resp2 = client.post("/ingest", json={"packets": [second]})

    incident_id_1 = resp1.json()["accepted"][0]["incident_id"]
    incident_id_2 = resp2.json()["accepted"][0]["incident_id"]

    assert incident_id_1 != incident_id_2