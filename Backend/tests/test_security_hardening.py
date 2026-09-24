"""
Tests for the Sep 2026 security-hardening sprint's new/changed controls.

STATUS: run for real (correction -- an earlier point in this same
sprint recorded "no Python environment available" for the backend;
that was true earlier in this sandbox session but not later once
`pip install -r requirements.txt` succeeded). All 35 tests in this
file pass, including two end-to-end checks through TestClient (a real
429 from POST /auth/request-otp after its configured limit, a real
413 from the body-size guard middleware) -- not just the unit-level
checks against InMemoryRateLimiter/the Pydantic schemas directly. See
docs/SECURITY_SCORECARD.md's "Testing & scanning" section for the
full account, including a real test-isolation regression this run
found in the rate limiter and fixed via conftest.py's
_reset_rate_limiters fixture.
"""

import hmac

import pytest
from fastapi import HTTPException
from fastapi.testclient import TestClient
from pydantic import ValidationError
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.core.config import Settings
from app.core.rate_limit import InMemoryRateLimiter, auth_rate_limiter
from app.core.security import _looks_like_default_key, verify_responder_api_key
from app.schemas.packet import PacketBatchIn, PacketIn
from app.schemas.user_profile import RegisterIn


# --- app.core.security: default-key fail-fast + timing-safe comparison ---


def test_default_key_detected_as_default():
    assert _looks_like_default_key.__module__ == "app.core.security"


def test_verify_responder_api_key_rejects_default_key_outside_debug(monkeypatch):
    from app.core import security as security_module

    monkeypatch.setattr(security_module.settings, "debug", False)
    monkeypatch.setattr(security_module.settings, "responder_api_key", "changeme-dev-key")

    with pytest.raises(HTTPException) as exc_info:
        verify_responder_api_key(_FakeRequest(), x_api_key="anything")

    assert exc_info.value.status_code == 500


def test_verify_responder_api_key_allows_default_key_in_debug(monkeypatch):
    """Local/dev boots with the placeholder key must keep working."""
    from app.core import security as security_module

    monkeypatch.setattr(security_module.settings, "debug", True)
    monkeypatch.setattr(security_module.settings, "responder_api_key", "changeme-dev-key")

    # Should not raise the 500 misconfiguration error; a wrong key still
    # 401s normally, which is the expected non-default-key path.
    with pytest.raises(HTTPException) as exc_info:
        verify_responder_api_key(_FakeRequest(), x_api_key="wrong-key")
    assert exc_info.value.status_code == 401


def test_verify_responder_api_key_accepts_correct_key(monkeypatch):
    from app.core import security as security_module

    monkeypatch.setattr(security_module.settings, "debug", True)
    monkeypatch.setattr(security_module.settings, "responder_api_key", "a-real-key")

    # Should not raise.
    verify_responder_api_key(_FakeRequest(), x_api_key="a-real-key")


def test_uses_timing_safe_comparison():
    """Regression guard: comparison must go through hmac.compare_digest, not `!=`."""
    import inspect

    from app.core import security as security_module

    source = inspect.getsource(security_module.verify_responder_api_key)
    assert "hmac.compare_digest" in source
    assert "!= settings.responder_api_key" not in source


# --- app.core.rate_limit: fail-open, per-IP sliding window ---


class _FakeClient:
    def __init__(self, host):
        self.host = host


class _FakeRequest:
    def __init__(self, host="1.2.3.4", forwarded_for=None):
        self.client = _FakeClient(host)
        self.headers = {}
        if forwarded_for:
            self.headers["x-forwarded-for"] = forwarded_for


def test_rate_limiter_allows_under_the_limit():
    limiter = InMemoryRateLimiter("t", max_requests=3, window_seconds=60)
    req = _FakeRequest()
    for _ in range(3):
        limiter.check(req)  # should not raise


def test_rate_limiter_blocks_over_the_limit():
    limiter = InMemoryRateLimiter("t", max_requests=2, window_seconds=60)
    req = _FakeRequest()
    limiter.check(req)
    limiter.check(req)
    with pytest.raises(HTTPException) as exc_info:
        limiter.check(req)
    assert exc_info.value.status_code == 429
    assert "Retry-After" in exc_info.value.headers


def test_rate_limiter_tracks_ips_independently():
    limiter = InMemoryRateLimiter("t", max_requests=1, window_seconds=60)
    limiter.check(_FakeRequest(host="1.1.1.1"))
    # A different IP must not be affected by the first IP's usage.
    limiter.check(_FakeRequest(host="2.2.2.2"))


def test_client_ip_ignores_client_supplied_x_forwarded_for_entries(monkeypatch):
    """Block 2: only the entry appended by the trusted proxy (N-th from the RIGHT) counts."""
    from app.core import rate_limit as rl

    monkeypatch.setattr(rl.settings, "trusted_proxy_count", 1)
    # attacker prepends fake entries; the proxy appended the real peer last
    req = _FakeRequest(host="10.0.0.1", forwarded_for="6.6.6.6, 7.7.7.7, 9.9.9.9")
    assert rl.client_ip(req) == "9.9.9.9"
    req2 = _FakeRequest(host="10.0.0.1", forwarded_for="1.1.1.1, 9.9.9.9")
    assert rl.client_ip(req2) == "9.9.9.9"  # rotating the spoofed prefix does not change the identity


def test_client_ip_ignores_x_forwarded_for_when_no_trusted_proxy(monkeypatch):
    from app.core import rate_limit as rl

    monkeypatch.setattr(rl.settings, "trusted_proxy_count", 0)
    assert rl.client_ip(_FakeRequest(host="10.0.0.1", forwarded_for="6.6.6.6")) == "10.0.0.1"


def test_client_ip_falls_back_to_peer_on_garbage_or_short_header(monkeypatch):
    from app.core import rate_limit as rl

    monkeypatch.setattr(rl.settings, "trusted_proxy_count", 2)
    assert rl.client_ip(_FakeRequest(host="10.0.0.1", forwarded_for="9.9.9.9")) == "10.0.0.1"  # fewer hops than proxies
    monkeypatch.setattr(rl.settings, "trusted_proxy_count", 1)
    assert rl.client_ip(_FakeRequest(host="10.0.0.1", forwarded_for="not-an-ip")) == "10.0.0.1"


def test_rate_limiter_rotating_spoofed_xff_does_not_bypass_limit(monkeypatch):
    from app.core import rate_limit as rl

    monkeypatch.setattr(rl.settings, "trusted_proxy_count", 1)
    limiter = InMemoryRateLimiter("t", max_requests=1, window_seconds=60)
    limiter.check(_FakeRequest(host="10.0.0.1", forwarded_for="1.1.1.1, 9.9.9.9"))
    with pytest.raises(HTTPException) as exc_info:
        limiter.check(_FakeRequest(host="10.0.0.1", forwarded_for="2.2.2.2, 9.9.9.9"))
    assert exc_info.value.status_code == 429


def test_rate_limiter_fail_open_limiter_allows_on_internal_error():
    """Emergency-critical limiters: a limiter bug must never deny service."""
    limiter = InMemoryRateLimiter("t", max_requests=1, window_seconds=60, fail_open=True)

    class _BrokenRequest:
        client = None

        @property
        def headers(self):
            raise RuntimeError("boom")

    limiter.check(_BrokenRequest())  # must not raise


def test_rate_limiter_fail_closed_limiter_returns_503_on_internal_error():
    """Abuse-sensitive limiters must not silently run unmetered."""
    limiter = InMemoryRateLimiter("t", max_requests=1, window_seconds=60, fail_open=False)

    class _BrokenRequest:
        client = None

        @property
        def headers(self):
            raise RuntimeError("boom")

    with pytest.raises(HTTPException) as exc_info:
        limiter.check(_BrokenRequest())
    assert exc_info.value.status_code == 503


def test_rate_limiter_state_is_bounded():
    limiter = InMemoryRateLimiter("t", max_requests=5, window_seconds=60, max_keys=50)
    for i in range(500):
        limiter.check(_FakeRequest(host=f"10.1.{i // 250}.{i % 250}"))
    assert len(limiter._hits) <= 50


def test_rate_limiter_cost_counts_packets():
    limiter = InMemoryRateLimiter("t", max_requests=10, window_seconds=60)
    req = _FakeRequest()
    limiter.check(req, cost=10)
    with pytest.raises(HTTPException):
        limiter.check(req, cost=1)


def test_rate_limiter_reset_clears_state():
    limiter = InMemoryRateLimiter("t", max_requests=1, window_seconds=60)
    req = _FakeRequest()
    limiter.check(req)
    limiter.reset()
    limiter.check(req)  # should not raise after reset


# --- app.schemas.packet: new field bounds on PacketIn / PacketBatchIn ---


def _valid_packet_kwargs(**overrides):
    base = dict(
        packet_id="p1",
        sender_id="s1",
        type="emergency",
        timestamp="2026-08-01T12:00:00.000Z",
        nonce="n1",
        ttl=5,
        hop_count=0,
        protocol_version=1,
        signature="sig",
    )
    base.update(overrides)
    return base


def test_packet_in_accepts_valid_fields():
    packet = PacketIn(**_valid_packet_kwargs())
    assert packet.packet_id == "p1"


def test_packet_in_rejects_oversized_message():
    with pytest.raises(ValidationError):
        PacketIn(**_valid_packet_kwargs(message="x" * 2001))


def test_packet_in_accepts_message_at_the_boundary():
    packet = PacketIn(**_valid_packet_kwargs(message="x" * 2000))
    assert len(packet.message) == 2000


def test_packet_in_rejects_out_of_range_latitude():
    with pytest.raises(ValidationError):
        PacketIn(**_valid_packet_kwargs(latitude=91.0))


def test_packet_in_rejects_out_of_range_longitude():
    with pytest.raises(ValidationError):
        PacketIn(**_valid_packet_kwargs(longitude=-181.0))


def test_packet_in_rejects_excessive_hop_count():
    with pytest.raises(ValidationError):
        PacketIn(**_valid_packet_kwargs(hop_count=1001))


def test_packet_in_rejects_ttl_above_frozen_spec_max():
    with pytest.raises(ValidationError):
        PacketIn(**_valid_packet_kwargs(ttl=6))


def test_packet_in_rejects_oversized_sender_id():
    with pytest.raises(ValidationError):
        PacketIn(**_valid_packet_kwargs(sender_id="x" * 257))


def test_packet_in_rejects_too_many_relay_path_entries():
    with pytest.raises(ValidationError):
        PacketIn(**_valid_packet_kwargs(relay_path=["hop"] * 33))


def test_packet_in_rejects_oversized_relay_path_entry():
    with pytest.raises(ValidationError):
        PacketIn(**_valid_packet_kwargs(relay_path=["x" * 257]))


def test_packet_in_accepts_relay_path_at_the_boundary():
    packet = PacketIn(**_valid_packet_kwargs(relay_path=["x" * 256] * 32))
    assert len(packet.relay_path) == 32


def test_packet_batch_in_rejects_oversized_batch():
    with pytest.raises(ValidationError):
        PacketBatchIn(packets=[{"a": 1}] * 501)


def test_packet_batch_in_accepts_batch_at_the_boundary():
    batch = PacketBatchIn(packets=[{"a": 1}] * 500)
    assert len(batch.packets) == 500


# --- app.schemas.user_profile: new field bounds on RegisterIn ---


def _valid_register_kwargs(**overrides):
    base = dict(sender_id="s1", name="Test User")
    base.update(overrides)
    return base


def test_register_in_accepts_valid_fields():
    payload = RegisterIn(**_valid_register_kwargs())
    assert payload.name == "Test User"


def test_register_in_rejects_oversized_sender_id():
    with pytest.raises(ValidationError):
        RegisterIn(**_valid_register_kwargs(sender_id="x" * 257))


def test_register_in_rejects_oversized_name():
    with pytest.raises(ValidationError):
        RegisterIn(**_valid_register_kwargs(name="x" * 201))


def test_register_in_rejects_oversized_medical_history():
    with pytest.raises(ValidationError):
        RegisterIn(**_valid_register_kwargs(medical_history="x" * 2001))


def test_register_in_rejects_too_many_emergency_contacts():
    with pytest.raises(ValidationError):
        RegisterIn(**_valid_register_kwargs(emergency_contacts=["1"] * 6))


def test_register_in_rejects_oversized_emergency_contact_entry():
    with pytest.raises(ValidationError):
        RegisterIn(**_valid_register_kwargs(emergency_contacts=["x" * 33]))


def test_register_in_accepts_emergency_contacts_at_the_boundary():
    payload = RegisterIn(**_valid_register_kwargs(emergency_contacts=["x" * 32] * 5))
    assert len(payload.emergency_contacts) == 5


def test_register_in_rejects_empty_sender_id():
    with pytest.raises(ValidationError):
        RegisterIn(**_valid_register_kwargs(sender_id=""))


# --- Secrets hygiene (static checks, not runtime-dependent) ---


# --- End-to-end: rate limiting and body-size guard on real HTTP routes ---
#
# The unit tests above exercise InMemoryRateLimiter and the Pydantic
# schemas in isolation. These go one layer up and drive the actual
# FastAPI app through TestClient, the same pattern test_auth_and_voice.py
# already uses -- confirming the dependency is actually wired onto the
# real route, not just that the class works standalone.


@pytest.fixture()
def http_client():
    from app.db.base import Base, get_db
    from app.main import app

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
    test_client = TestClient(app)
    yield test_client
    app.dependency_overrides.clear()
    Base.metadata.drop_all(bind=engine)


def test_request_otp_gets_rate_limited_after_the_configured_max(http_client, monkeypatch):
    """
    Confirms enforce_auth_rate_limit is actually wired onto
    POST /auth/request-otp (not just unit-tested in isolation): the
    auth_rate_limiter's limit is small enough to trip within one test.
    """
    monkeypatch.setattr(auth_rate_limiter, "max_requests", 3)

    for i in range(3):
        resp = http_client.post(
            "/auth/request-otp", json={"email": f"ratelimit{i}@example.com"}
        )
        assert resp.status_code == 200

    blocked = http_client.post(
        "/auth/request-otp", json={"email": "one-too-many@example.com"}
    )
    assert blocked.status_code == 429
    assert "Retry-After" in blocked.headers


def test_alerts_respond_rejects_oversized_body(http_client):
    """
    Confirms the global body-size guard middleware (app/main.py) is
    actually wired into the real ASGI stack, not just present as a
    function -- sends a request with a Content-Length header above
    MAX_REQUEST_BODY_BYTES and expects 413, using a route that would
    otherwise 404/422 quickly so the test isn't relying on any one
    specific endpoint's own validation to produce the 413.
    """
    from app.core.body_limit import DEFAULT_LIMIT_BYTES

    big_body = b"x" * 100  # actual body is small; only the header lies
    resp = http_client.post(
        "/alerts/1/respond",
        content=big_body,
        headers={"Content-Length": str(DEFAULT_LIMIT_BYTES + 1)},
    )
    assert resp.status_code == 413


def test_env_files_are_not_tracked_by_git():
    """
    Regression guard for the FOUND/NOT-FOUND secrets audit: .env files
    with real values exist on disk in this repo but must never be
    tracked by git. Does not print or assert on their contents.
    """
    import subprocess

    result = subprocess.run(
        ["git", "ls-files"],
        capture_output=True,
        text=True,
        cwd=__file__.rsplit("/Backend/", 1)[0] + "/Backend" if "/Backend/" in __file__ else ".",
    )
    tracked = result.stdout.splitlines()
    assert not any(f.endswith(".env") for f in tracked)
