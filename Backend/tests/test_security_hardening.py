"""
Tests for the Sep 2026 security-hardening sprint's new/changed controls.

STATUS: written this sprint but NOT EXECUTED -- this sandbox has no
Python environment (fastapi/pydantic/etc. are not installed and could
not be installed here; see docs/SECURITY_SCORECARD.md's "Testing &
scanning" section). These tests are written to the same style and
fixture conventions as the rest of Backend/tests/ (see conftest.py,
test_config.py) so they should be runnable as-is in a real environment
(`pytest Backend/tests/test_security_hardening.py`), but that has not
been verified by an actual run. Do not treat this file's presence as
evidence the controls were tested -- only that they were reasoned
through carefully.
"""

import hmac

import pytest
from fastapi import HTTPException
from pydantic import ValidationError

from app.core.config import Settings
from app.core.rate_limit import InMemoryRateLimiter
from app.core.security import _looks_like_default_key, verify_responder_api_key
from app.schemas.packet import PacketBatchIn, PacketIn


# --- app.core.security: default-key fail-fast + timing-safe comparison ---


def test_default_key_detected_as_default():
    assert _looks_like_default_key.__module__ == "app.core.security"


def test_verify_responder_api_key_rejects_default_key_outside_debug(monkeypatch):
    from app.core import security as security_module

    monkeypatch.setattr(security_module.settings, "debug", False)
    monkeypatch.setattr(security_module.settings, "responder_api_key", "changeme-dev-key")

    with pytest.raises(HTTPException) as exc_info:
        verify_responder_api_key(x_api_key="anything")

    assert exc_info.value.status_code == 500


def test_verify_responder_api_key_allows_default_key_in_debug(monkeypatch):
    """Local/dev boots with the placeholder key must keep working."""
    from app.core import security as security_module

    monkeypatch.setattr(security_module.settings, "debug", True)
    monkeypatch.setattr(security_module.settings, "responder_api_key", "changeme-dev-key")

    # Should not raise the 500 misconfiguration error; a wrong key still
    # 401s normally, which is the expected non-default-key path.
    with pytest.raises(HTTPException) as exc_info:
        verify_responder_api_key(x_api_key="wrong-key")
    assert exc_info.value.status_code == 401


def test_verify_responder_api_key_accepts_correct_key(monkeypatch):
    from app.core import security as security_module

    monkeypatch.setattr(security_module.settings, "debug", True)
    monkeypatch.setattr(security_module.settings, "responder_api_key", "a-real-key")

    # Should not raise.
    verify_responder_api_key(x_api_key="a-real-key")


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
    limiter = InMemoryRateLimiter(max_requests=3, window_seconds=60)
    req = _FakeRequest()
    for _ in range(3):
        limiter.check(req)  # should not raise


def test_rate_limiter_blocks_over_the_limit():
    limiter = InMemoryRateLimiter(max_requests=2, window_seconds=60)
    req = _FakeRequest()
    limiter.check(req)
    limiter.check(req)
    with pytest.raises(HTTPException) as exc_info:
        limiter.check(req)
    assert exc_info.value.status_code == 429
    assert "Retry-After" in exc_info.value.headers


def test_rate_limiter_tracks_ips_independently():
    limiter = InMemoryRateLimiter(max_requests=1, window_seconds=60)
    limiter.check(_FakeRequest(host="1.1.1.1"))
    # A different IP must not be affected by the first IP's usage.
    limiter.check(_FakeRequest(host="2.2.2.2"))


def test_rate_limiter_prefers_x_forwarded_for():
    limiter = InMemoryRateLimiter(max_requests=1, window_seconds=60)
    limiter.check(_FakeRequest(host="10.0.0.1", forwarded_for="9.9.9.9, 10.0.0.1"))
    with pytest.raises(HTTPException):
        # Same forwarded client, different proxy hop host -- should
        # still be recognized as the same limited client.
        limiter.check(_FakeRequest(host="10.0.0.2", forwarded_for="9.9.9.9, 10.0.0.2"))


def test_rate_limiter_fails_open_on_internal_error():
    """A limiter bug must never become a second way to deny service."""
    limiter = InMemoryRateLimiter(max_requests=1, window_seconds=60)

    class _BrokenRequest:
        @property
        def headers(self):
            raise RuntimeError("boom")

    # Must not raise -- fail-open swallows the internal error.
    limiter.check(_BrokenRequest())


def test_rate_limiter_reset_clears_state():
    limiter = InMemoryRateLimiter(max_requests=1, window_seconds=60)
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


# --- Secrets hygiene (static checks, not runtime-dependent) ---


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
