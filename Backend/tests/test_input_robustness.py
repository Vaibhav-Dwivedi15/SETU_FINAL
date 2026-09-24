"""Block 2 -- controlled 4xx for malformed public input; never a traceback to the client."""

import pytest
from fastapi.testclient import TestClient

from app.main import app
from tests.signing_helpers import register_profile
from tests.test_government_and_alerts import TEST_API_KEY
from tests.test_ingest import client, make_emergency  # noqa: F401
from tests.test_request_auth import new_key

H = {"x-api-key": TEST_API_KEY}


@pytest.fixture()
def authed(client):
    from app.core.config import settings
    original = settings.responder_api_key
    settings.responder_api_key = TEST_API_KEY
    yield client
    settings.responder_api_key = original


class TestPathAndQueryBounds:
    @pytest.mark.parametrize("incident_id", ["99999999999999999999", "0", "-1", "abc", "1.5", "2147483648"])
    def test_bad_incident_ids_are_422(self, authed, incident_id):
        for method, path in (
            ("get", f"/incidents/{incident_id}/profile"),
            ("get", f"/incidents/{incident_id}/history"),
            ("get", f"/incidents/{incident_id}/responses"),
            ("get", f"/incidents/{incident_id}/government-notifications"),
            ("post", f"/incidents/{incident_id}/resolve"),
        ):
            resp = getattr(authed, method)(path, headers=H)
            assert resp.status_code == 422, (path, resp.status_code)

    def test_respond_rejects_bad_ids_and_types(self, client):
        from tests.signing_helpers import pubkey_hex, signed_json_post
        key = new_key()
        me = pubkey_hex(key)
        assert signed_json_post(client, key, "/alerts/99999999999999999999/respond", {"sender_id": me, "response_type": "NEARBY"}).status_code == 422
        assert signed_json_post(client, key, "/alerts/1/respond", {"sender_id": "x" * 300, "response_type": "NEARBY"}).status_code == 422
        assert signed_json_post(client, key, "/alerts/1/respond", {"sender_id": me, "response_type": "NOPE"}).status_code == 422
        # unauthenticated callers are refused outright (401), never reaching the database
        assert client.post("/alerts/1/respond", json={"sender_id": me, "response_type": "NEARBY"}).status_code == 401

    def test_infinite_or_nan_coordinates_rejected_per_packet(self, client):
        import json as _json
        good = make_emergency(packet_id="ok2", emergency_id="e-ok2")
        raw = _json.dumps({"packets": [good, make_emergency(packet_id="inf1", emergency_id="e-inf")]}).replace('"latitude": 28.6139', '"latitude": Infinity', 2)
        body = client.post("/ingest", content=raw, headers={"Content-Type": "application/json"}).json()
        assert all(e["status"] == "REJECTED" for e in body["rejected"]) and body["rejected"]
        assert body["accepted"] == []

    @pytest.mark.parametrize("params", [
        {"lat": "nan", "lon": "0"}, {"lat": "abc", "lon": "0"}, {"lat": "91", "lon": "0"},
        {"lat": "0", "lon": "-181"}, {"lat": "0", "lon": "0", "radius_km": "0"},
        {"lat": "0", "lon": "0", "radius_km": "-1"}, {"lat": "0", "lon": "0", "radius_km": "16"}, {"lat": "0"},
    ])
    def test_nearby_bad_query_is_422_before_auth_work(self, client, params):
        assert client.get("/alerts/nearby", params=params).status_code == 422

    def test_responder_registry_bounds(self, authed):
        assert authed.post("/responders", json={"public_key": "k" * 300, "name": "n"}, headers=H).status_code == 422
        assert authed.post("/responders", json={"public_key": "", "name": "n"}, headers=H).status_code == 422
        assert authed.post("/responders", json={"public_key": "k", "name": "n" * 300}, headers=H).status_code == 422

    def test_otp_sender_id_bounded(self, client):
        assert client.post("/auth/request-otp", json={"email": "a@example.com", "sender_id": "s" * 300}).status_code == 422


class TestIngestEnvelope:
    @pytest.mark.parametrize("body", [b"", b"null", b"[]", b'{"packets": null}', b'{"packets": "x"}', b'{"packets": {}}', b'{"nope": 1}'])
    def test_bad_envelopes_are_422(self, client, body):
        resp = client.post("/ingest", content=body, headers={"Content-Type": "application/json"})
        assert resp.status_code == 422 and "Traceback" not in resp.text

    def test_wrong_content_type_is_controlled(self, client):
        resp = client.post("/ingest", content=b"packets=1", headers={"Content-Type": "text/plain"})
        assert 400 <= resp.status_code < 500

    @pytest.mark.parametrize("field,value", [
        ("latitude", "28.6abc"), ("longitude", 200), ("ttl", "five"), ("hop_count", -1),
        ("packet_id", ""), ("packet_id", "x" * 300), ("sender_id", ""), ("nonce", ""), ("protocol_version", 0),
        ("relay_path", ["x"] * 40), ("priority", "urgent"), ("incident_type", "aliens"), ("message", "x" * 2001),
    ])
    def test_bad_field_values_reject_only_that_packet(self, client, field, value):
        good = make_emergency(packet_id="ok1", emergency_id="e-ok1")
        bad = make_emergency(packet_id="bad1", emergency_id="e-bad1")
        bad[field] = value
        body = client.post("/ingest", json={"packets": [bad, good]}).json()
        assert [e["packet_id"] for e in body["accepted"]] == ["ok1"]
        assert len(body["rejected"]) == 1 and body["rejected"][0]["status"] == "REJECTED"

    def test_deeply_nested_json_packet_is_rejected_not_a_crash(self, client):
        nested = current = {}
        for _ in range(500):
            current["a"] = {}
            current = current["a"]
        resp = client.post("/ingest", json={"packets": [nested, make_emergency()]})
        assert resp.status_code in (200, 400, 413, 422)
        assert "Traceback" not in resp.text


class TestNoTracebackLeak:
    def test_unhandled_exception_becomes_generic_json_500(self, monkeypatch):
        import app.routers.ingest as ingest_router

        def boom(*a, **k):
            raise RuntimeError("secret internal detail /home/x/app.py SELECT * FROM users")

        monkeypatch.setattr(ingest_router, "process_batch", boom)
        quiet = TestClient(app, raise_server_exceptions=False)
        resp = quiet.post("/ingest", json={"packets": []})
        assert resp.status_code == 500
        assert resp.json() == {"detail": "Internal server error."}
        assert "secret" not in resp.text and "SELECT" not in resp.text and "Traceback" not in resp.text

    def test_database_failure_in_one_packet_is_FAILED_retryable_not_500(self, client, monkeypatch):
        import app.services.ingest_service as svc

        def boom(*a, **k):
            raise RuntimeError("db exploded")

        monkeypatch.setattr(svc, "process_sos_packet", boom)
        resp = client.post("/ingest", json={"packets": [make_emergency(packet_id="dbf", emergency_id="e-dbf")]})
        assert resp.status_code == 200
        entry = resp.json()["failed"][0]
        assert entry["status"] == "FAILED" and entry["retryable"] is True
        assert "db exploded" not in resp.text
        # and the failed attempt left nothing behind that would make the retry a "duplicate"
        monkeypatch.undo()
        retry = client.post("/ingest", json={"packets": [make_emergency(packet_id="dbf", emergency_id="e-dbf")]}).json()
        assert retry["duplicates"] == [] and len(retry["accepted"]) == 1
