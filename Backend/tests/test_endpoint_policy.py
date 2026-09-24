"""
Block 3 -- every route has a declared access class, and each class is enforced.

PUBLIC     no credential by design (health, public keys, OTP, login exchange)
INGEST     no credential BY DESIGN: mandatory Ed25519 packet signature instead (offline
           exit nodes must be able to deliver; see docs/security/ENDPOINT_POLICY.md)
DEVICE     request signed by a device Ed25519 key (X-Setu-*) -- PoP
RESPONDER  responder session token or responder key
ADMIN      admin key only (a session token never qualifies)

Adding a route without classifying it fails this test.
"""

import pytest

from app.main import app
from tests.test_ingest import client  # noqa: F401

POLICY = {
    ("GET", "/"): "PUBLIC",
    ("GET", "/health"): "PUBLIC",
    ("GET", "/ingest/voice/status"): "PUBLIC",
    ("GET", "/responders/keys"): "PUBLIC",
    ("POST", "/auth/request-otp"): "PUBLIC",
    ("POST", "/auth/verify-otp"): "PUBLIC",
    ("POST", "/auth/responder-login"): "PUBLIC",
    ("POST", "/ingest"): "INGEST",
    ("POST", "/register"): "DEVICE",
    ("POST", "/ingest/voice"): "DEVICE",
    ("GET", "/alerts/nearby"): "DEVICE",
    ("POST", "/alerts/{incident_id}/respond"): "DEVICE",
    ("GET", "/incidents"): "RESPONDER",
    ("POST", "/incidents/{incident_id}/resolve"): "RESPONDER",
    ("GET", "/incidents/{incident_id}/profile"): "RESPONDER",
    ("GET", "/incidents/{incident_id}/history"): "RESPONDER",
    ("GET", "/incidents/{incident_id}/responses"): "RESPONDER",
    ("GET", "/incidents/{incident_id}/government-notifications"): "RESPONDER",
    ("GET", "/government/notifications"): "RESPONDER",
    ("GET", "/government/adapter-status"): "RESPONDER",
    ("GET", "/responders"): "RESPONDER",
    ("POST", "/responders"): "ADMIN",
    ("POST", "/responders/{public_key}/revoke"): "ADMIN",
}


def declared_routes():
    routes = set()
    for path, ops in app.openapi()["paths"].items():
        for method in ops:
            routes.add((method.upper(), path))
    return routes


def concrete(path):
    return path.replace("{incident_id}", "1").replace("{public_key}", "0" * 64)


def test_every_route_is_classified_and_nothing_stale_is_listed():
    assert declared_routes() == set(POLICY)


@pytest.mark.parametrize("route", sorted(k for k, v in POLICY.items() if v in ("RESPONDER", "ADMIN", "DEVICE")))
def test_privileged_routes_reject_anonymous_callers(client, route, monkeypatch):
    import app.routers.voice as voice_router
    monkeypatch.setattr(voice_router, "transcription_available", lambda: True)
    method, path = route
    kwargs = {"json": {}}
    if path == "/alerts/nearby":
        kwargs = {"params": {"lat": "1", "lon": "1", "radius_km": "1"}}
    elif path == "/ingest/voice":
        kwargs = {"files": {"file": ("a.wav", b"RIFF\x00\x00\x00\x00WAVEfmt " + b"\0" * 32, "audio/wav")}}
    resp = client.request(method, concrete(path), **kwargs)
    assert resp.status_code in (401, 403), (route, resp.status_code)


@pytest.mark.parametrize("route", sorted(k for k, v in POLICY.items() if v == "ADMIN"))
def test_admin_routes_reject_responder_credentials(client, route):
    from app.core.config import settings
    method, path = route
    settings.responder_api_key = "test-responder-api-key"
    token = client.post("/auth/responder-login", json={"key": "test-responder-api-key"}).json()["access_token"]
    for headers in ({"x-api-key": "test-responder-api-key"}, {"Authorization": f"Bearer {token}"}):
        resp = client.request(method, concrete(path), json={"public_key": "0" * 64, "name": "x"}, headers=headers)
        assert resp.status_code in (401, 403), (route, resp.status_code)


def test_ingest_still_requires_a_valid_signature_but_no_credential(client):
    from tests.test_ingest import make_emergency
    good = make_emergency()
    assert client.post("/ingest", json={"packets": [good]}).json()["accepted"]
    bad = dict(make_emergency(packet_id="p9", emergency_id="e9"), signature="00" * 64)
    assert client.post("/ingest", json={"packets": [bad]}).json()["rejected"][0]["code"] == "invalid_signature"


def test_docs_and_schema_are_not_exposed_in_production(client):
    for path in ("/docs", "/redoc", "/openapi.json"):
        assert client.get(path).status_code == 404


def test_api_security_headers_present(client):
    for path in ("/health", "/incidents", "/responders/keys"):
        h = client.get(path).headers
        assert h["x-content-type-options"] == "nosniff"
        assert h["cache-control"] == "no-store"
        assert h["referrer-policy"] == "no-referrer"
        assert h["x-frame-options"] == "DENY"
        assert "max-age=" in h["strict-transport-security"]
        assert "frame-ancestors 'none'" in h["content-security-policy"]
    assert client.post("/register", content=b"x" * 200_000, headers={"Content-Type": "application/json"}).headers["x-content-type-options"] == "nosniff"  # 413 too
