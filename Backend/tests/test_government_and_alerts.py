"""
Integration tests for Phase 2 (government notification adapter) and
Phase 3 (nearby community alerts + response actions).

Known gap closed: these endpoints existed with zero test coverage --
flagged explicitly in SETU_Ayush_Handoff_Aug24.md and every handoff
since. Follows the exact fixture/signing pattern test_ingest.py already
established (isolated in-memory SQLite per test, real Ed25519 signing
via the same _pubkey_hex_for/_sign_packet helpers), so these tests never
touch the real dev Postgres and stay consistent with the rest of the suite.
"""

from datetime import datetime, timezone
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

from tests.signing_helpers import register_profile, signed_json_post, signed_nearby, pubkey_hex

_DEVICE_KEYS: dict[str, Ed25519PrivateKey] = {}


def _private_key_for(device_name: str) -> Ed25519PrivateKey:
    if device_name not in _DEVICE_KEYS:
        _DEVICE_KEYS[device_name] = Ed25519PrivateKey.generate()
    return _DEVICE_KEYS[device_name]


def _pubkey_hex_for(device_name: str) -> str:
    return _private_key_for(device_name).public_key().public_bytes_raw().hex()


def _sign_packet(packet: dict, device_name: str) -> str:
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


def _key_for_sender(sender_id: str) -> Ed25519PrivateKey:
    for key in _DEVICE_KEYS.values():
        if pubkey_hex(key) == sender_id:
            return key
    raise KeyError(sender_id)


def _ensure_registered(client, private_key) -> None:
    registered = client.__dict__.setdefault("_registered_devices", set())
    if pubkey_hex(private_key) not in registered:
        resp = register_profile(client, private_key, name="Community Tester")
        assert resp.status_code == 200, resp.text
        registered.add(pubkey_hex(private_key))


def _nearby(client, params, viewer="community-viewer"):
    """Signed, registered /alerts/nearby call (Block 2: anonymous callers are refused)."""
    key = _key_for_sender(params["sender_id"]) if "sender_id" in params else _private_key_for(viewer)
    _ensure_registered(client, key)
    return signed_nearby(client, key, params)


def _respond(client, incident_id, payload):
    key = _key_for_sender(payload["sender_id"])
    _ensure_registered(client, key)
    return signed_json_post(client, key, f"/alerts/{incident_id}/respond", payload)


def make_emergency(packet_id="gp1", emergency_id="ge1", sender_id="gov-dev-1",
                    latitude=28.6139, longitude=77.2090, incident_type="fire"):
    real_sender_id = _pubkey_hex_for(sender_id)
    packet = {
        "packet_id": packet_id,
        "sender_id": real_sender_id,
        "type": "emergency",
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "nonce": f"nonce-{packet_id}",
        "ttl": 5,
        "hop_count": 0,
        "protocol_version": 1,
        "emergency_id": emergency_id,
        "latitude": latitude,
        "longitude": longitude,
        "message": "test emergency for government/alerts tests",
        "priority": "high",
        "incident_type": incident_type,
    }
    packet["signature"] = _sign_packet(packet, sender_id)
    return packet


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

    original_api_key = settings.responder_api_key
    settings.responder_api_key = TEST_API_KEY

    test_client = TestClient(app)
    yield test_client

    settings.responder_api_key = original_api_key
    app.dependency_overrides.clear()
    Base.metadata.drop_all(bind=engine)


def _create_incident(client) -> int:
    """Ingests one emergency packet and returns the resulting incident_id."""
    packet = make_emergency()
    resp = client.post("/ingest", json={"packets": [packet]})
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert len(body["accepted"]) == 1, body
    return body["accepted"][0]["incident_id"]


# ============================================================
# Phase 2 -- Government notification adapter
# ============================================================

class TestGovernmentNotifications:
    def test_new_incident_creates_a_sent_mock_notification(self, client):
        """
        The adapter fires non-blocking, after commit, only for genuinely
        new incidents (see incident_service.handle_sos_packet) -- this
        confirms the whole chain actually produces a visible, correctly
        marked-as-mock row.
        """
        incident_id = _create_incident(client)

        resp = client.get(
            f"/incidents/{incident_id}/government-notifications",
            headers={"x-api-key": TEST_API_KEY},
        )
        assert resp.status_code == 200, resp.text
        rows = resp.json()
        assert len(rows) == 1
        assert rows[0]["status"] == "SENT"
        assert rows[0]["is_mock"] is True
        assert rows[0]["adapter_name"] == "mock"
        # MOCK-GOV- prefix is a deliberate never-mistake-for-real marker
        # -- see government_notification_service.py's MockGovernmentAdapter.
        assert rows[0]["reference_id"].startswith("MOCK-GOV-")

    def test_corroborating_report_does_not_duplicate_notification(self, client):
        """
        Same rule as SMS notification: a merge into an existing OPEN
        incident must not fire a second government notification -- only
        genuinely new incidents do.
        """
        first = make_emergency(packet_id="gp-dup-1", emergency_id="ge-dup",
                                sender_id="gov-dev-a")
        second = make_emergency(packet_id="gp-dup-2", emergency_id="ge-dup",
                                 sender_id="gov-dev-b")

        resp1 = client.post("/ingest", json={"packets": [first]})
        assert resp1.status_code == 200, resp1.text
        incident_id = resp1.json()["accepted"][0]["incident_id"]

        resp2 = client.post("/ingest", json={"packets": [second]})
        assert resp2.status_code == 200, resp2.text

        gov_resp = client.get(
            f"/incidents/{incident_id}/government-notifications",
            headers={"x-api-key": TEST_API_KEY},
        )
        assert gov_resp.status_code == 200
        # Still exactly one -- the merge must not have fired a second call.
        assert len(gov_resp.json()) == 1

    def test_government_notifications_require_api_key(self, client):
        incident_id = _create_incident(client)
        resp = client.get(f"/incidents/{incident_id}/government-notifications")
        assert resp.status_code in (401, 403)

    def test_government_notifications_404_for_unknown_incident(self, client):
        resp = client.get(
            "/incidents/999999/government-notifications",
            headers={"x-api-key": TEST_API_KEY},
        )
        assert resp.status_code == 404

    def test_adapter_status_reports_mock(self, client):
        _create_incident(client)
        resp = client.get(
            "/government/adapter-status",
            headers={"x-api-key": TEST_API_KEY},
        )
        assert resp.status_code == 200, resp.text
        body = resp.json()
        assert body["is_mock"] is True
        assert body["adapter_name"] == "mock"
        assert body["total_notifications"] >= 1

    def test_list_all_government_notifications(self, client):
        _create_incident(client)
        resp = client.get(
            "/government/notifications",
            headers={"x-api-key": TEST_API_KEY},
        )
        assert resp.status_code == 200, resp.text
        assert len(resp.json()) >= 1


# ============================================================
# Phase 3 -- Nearby community alerts + response actions
# ============================================================

class TestNearbyAlerts:
    def test_nearby_returns_open_incident_within_radius(self, client):
        incident_id = _create_incident(client)  # lat/lng: 28.6139, 77.2090 (Delhi)

        resp = _nearby(client, {"lat": 28.6139, "lon": 77.2090, "radius_km": 5})
        assert resp.status_code == 200, resp.text
        results = resp.json()
        assert any(r["incident_id"] == incident_id for r in results)

    def test_nearby_excludes_incidents_outside_radius(self, client):
        _create_incident(client)  # Delhi

        # Mumbai -- roughly 1400km from Delhi, well outside a 5km radius.
        resp = _nearby(client, {"lat": 19.0760, "lon": 72.8777, "radius_km": 5})
        assert resp.status_code == 200, resp.text
        assert resp.json() == []

    def test_nearby_response_never_exposes_reporter_identity(self, client):
        """
        Hard privacy requirement, per nearby_alert_service.py's own
        module docstring: /alerts/nearby must never leak sender_id or
        any profile field for the reporting victim.
        """
        _create_incident(client)

        resp = _nearby(client, {"lat": 28.6139, "lon": 77.2090, "radius_km": 5})
        assert resp.status_code == 200
        for row in resp.json():
            assert "sender_id" not in row
            assert "name" not in row
            assert "profile" not in row
            assert set(row.keys()) <= {
                "incident_id", "incident_type", "sender_priority",
                "ai_priority", "distance_km", "created_at", "message",
            }

    def test_nearby_message_matches_spec_wording(self, client):
        _create_incident(client)
        resp = _nearby(client, {"lat": 28.6139, "lon": 77.2090, "radius_km": 5})
        results = resp.json()
        assert len(results) >= 1
        assert results[0]["message"] == (
            "An emergency has been reported near your area. "
            "If you are safe and able to help, please open SETU for details."
        )

    def test_nearby_radius_is_capped(self, client):
        """
        MAX_RADIUS_KM in nearby_alert_service.py caps the query even if
        a client requests something huge -- this confirms the API layer
        (Query(..., le=MAX_RADIUS_KM)) actually rejects an over-limit
        value rather than silently clamping (422, not 200).
        """
        resp = _nearby(client, {"lat": 28.6139, "lon": 77.2090, "radius_km": 9999})
        assert resp.status_code == 422

    def test_respond_creates_a_response(self, client):
        incident_id = _create_incident(client)
        sender_id = _pubkey_hex_for("responder-community-1")

        resp = _respond(client, incident_id, {"sender_id": sender_id, "response_type": "CAN_HELP"})
        assert resp.status_code == 200, resp.text
        body = resp.json()
        assert body["response_type"] == "CAN_HELP"
        assert body["incident_id"] == incident_id

    def test_respond_twice_updates_not_duplicates(self, client):
        """
        CommunityResponse is upserted by (incident_id, sender_id) -- a
        second response from the same sender must update the existing
        row, never create a second one.
        """
        incident_id = _create_incident(client)
        sender_id = _pubkey_hex_for("responder-community-2")

        first = _respond(client, incident_id, {"sender_id": sender_id, "response_type": "NEARBY"})
        assert first.status_code == 200
        first_id = first.json()["id"]

        second = _respond(client, incident_id, {"sender_id": sender_id, "response_type": "ALREADY_RESPONDING"})
        assert second.status_code == 200
        assert second.json()["id"] == first_id
        assert second.json()["response_type"] == "ALREADY_RESPONDING"

        # Confirm exactly one row exists via the responder-facing list.
        listing = client.get(
            f"/incidents/{incident_id}/responses",
            headers={"x-api-key": TEST_API_KEY},
        )
        assert listing.status_code == 200
        assert len(listing.json()) == 1

    def test_respond_404_for_unknown_incident(self, client):
        sender_id = _pubkey_hex_for("responder-community-3")
        resp = _respond(client, 999999, {"sender_id": sender_id, "response_type": "CAN_HELP"})
        assert resp.status_code == 404

    def test_already_responded_excluded_from_next_fetch(self, client):
        """
        exclude_sender_id in get_nearby_open_incidents: once a sender has
        responded, that incident should no longer surface for them on
        the NEXT /alerts/nearby call (avoids re-surfacing an alert
        they've already acted on).
        """
        incident_id = _create_incident(client)
        sender_id = _pubkey_hex_for("responder-community-4")

        _respond(client, incident_id, {"sender_id": sender_id, "response_type": "NEARBY"})

        resp = _nearby(client, {"lat": 28.6139, "lon": 77.2090, "radius_km": 5, "sender_id": sender_id})
        assert resp.status_code == 200
        assert all(r["incident_id"] != incident_id for r in resp.json())

    def test_incident_responses_requires_api_key(self, client):
        incident_id = _create_incident(client)
        resp = client.get(f"/incidents/{incident_id}/responses")
        assert resp.status_code in (401, 403)
