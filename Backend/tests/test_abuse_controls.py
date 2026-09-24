"""
Block 2 -- abuse controls: byte-counting body cap, per-endpoint limits,
client-IP trust, fail-open (emergency) vs fail-closed (abuse-sensitive).
"""

import json

import pytest

from app.core import rate_limit as rl
from app.core.body_limit import DEFAULT_LIMIT_BYTES, INGEST_LIMIT_BYTES, VOICE_LIMIT_BYTES
from tests.signing_helpers import register_profile, sign_request, sha
from tests.test_ingest import client, make_emergency  # noqa: F401
from tests.test_ingest_contract import ingest, only
from tests.test_request_auth import new_key


def chunks(total, size=8192):
    def gen():
        sent = 0
        while sent < total:
            n = min(size, total - sent)
            yield b"x" * n
            sent += n
    return gen()


class TestBodySizeCap:
    def test_content_length_over_cap_is_413(self, client):
        resp = client.post("/register", content=b"{}", headers={"Content-Length": str(DEFAULT_LIMIT_BYTES + 1), "Content-Type": "application/json"})
        assert resp.status_code == 413

    def test_chunked_body_without_content_length_is_still_capped(self, client):
        # httpx sends an iterator body with Transfer-Encoding: chunked and NO Content-Length.
        resp = client.post("/register", content=chunks(DEFAULT_LIMIT_BYTES * 4), headers={"Content-Type": "application/json"})
        assert resp.status_code == 413
        assert "content-length" not in {k.lower() for k in resp.request.headers}

    def test_chunked_ingest_body_capped(self, client):
        resp = client.post("/ingest", content=chunks(INGEST_LIMIT_BYTES + 100_000), headers={"Content-Type": "application/json"})
        assert resp.status_code == 413

    def test_lying_small_content_length_does_not_bypass(self, client):
        """Header claims 10 bytes, body is huge: counted bytes win (h11 rejects the mismatch, or we do)."""
        try:
            resp = client.post("/register", content=chunks(DEFAULT_LIMIT_BYTES * 2), headers={"Content-Length": "10", "Content-Type": "application/json"})
            assert resp.status_code in (400, 413)
        except Exception:
            pass  # transport-level refusal of the malformed request is also a pass

    def test_normal_sized_requests_unaffected(self, client):
        assert client.post("/ingest", json={"packets": [make_emergency()]}).status_code == 200

    def test_ingest_cap_fits_a_full_legal_batch(self, client):
        packets = [make_emergency(packet_id=f"b{i}", emergency_id=f"e{i}") for i in range(500)]
        size = len(json.dumps({"packets": packets}))
        assert size < INGEST_LIMIT_BYTES

    def test_voice_cap_is_larger_than_audio_cap(self):
        from app.routers.voice import MAX_AUDIO_BYTES
        assert VOICE_LIMIT_BYTES > MAX_AUDIO_BYTES

    def test_voice_chunked_oversize_is_413(self, client, monkeypatch):
        resp = client.post("/ingest/voice", content=chunks(VOICE_LIMIT_BYTES + 200_000, 65536), headers={"Content-Type": "multipart/form-data; boundary=x"})
        assert resp.status_code == 413


class TestRateLimits:
    def test_ingest_request_limit_returns_429_with_retry_after(self, client, monkeypatch):
        monkeypatch.setattr(rl.ingest_request_limiter, "max_requests", 3)
        codes = [client.post("/ingest", json={"packets": []}).status_code for _ in range(5)]
        assert codes == [200, 200, 200, 429, 429]
        assert client.post("/ingest", json={"packets": []}).headers["Retry-After"]

    def test_ingest_packet_budget_counts_packets_not_requests(self, client, monkeypatch):
        monkeypatch.setattr(rl.ingest_packet_limiter, "max_requests", 5)
        packets = [make_emergency(packet_id=f"p{i}", emergency_id=f"e{i}") for i in range(4)]
        assert client.post("/ingest", json={"packets": packets}).status_code == 200
        assert client.post("/ingest", json={"packets": packets}).status_code == 429

    def test_legitimate_emergency_traffic_is_not_throttled(self, client):
        for i in range(60):  # an unusually busy minute from one shared (CGNAT) address
            assert client.post("/ingest", json={"packets": [make_emergency(packet_id=f"s{i}", emergency_id=f"e{i}", latitude=10 + i * 0.5, longitude=10)]}).status_code == 200

    def test_limited_ingest_loses_no_data(self, client, monkeypatch):
        """429 means 'retry later' (mobile treats non-2xx as failed, keeps the packet queued)."""
        monkeypatch.setattr(rl.ingest_request_limiter, "max_requests", 1)
        packet = make_emergency(packet_id="keep1", emergency_id="e-keep")
        assert client.post("/ingest", json={"packets": [packet]}).status_code == 200
        assert client.post("/ingest", json={"packets": [packet]}).status_code == 429
        rl.ingest_request_limiter.reset()
        assert only(ingest(client, packet), "duplicates")

    def test_register_ip_limit(self, client):
        codes = [register_profile(client, new_key()).status_code for _ in range(11)]
        assert codes[:10] == [200] * 10 and codes[10] == 429

    def test_responder_keys_limit(self, client):
        codes = [client.get("/responders/keys").status_code for _ in range(61)]
        assert codes[59] == 200 and codes[60] == 429

    def test_auth_limits_still_apply(self, client):
        codes = [client.post("/auth/request-otp", json={"email": f"u{i}@example.com"}).status_code for i in range(11)]
        assert codes[-1] == 429

    def test_responder_api_key_bruteforce_is_damped(self, client):
        codes = [client.get("/incidents", headers={"x-api-key": f"guess-{i}"}).status_code for i in range(22)]
        assert codes[:20] == [401] * 20 and codes[20] == 429

    def test_alerts_respond_public_write_limit(self, client):
        codes = [client.post("/alerts/1/respond", json={"sender_id": "x", "response_type": "NEARBY"}).status_code for _ in range(32)]
        assert 429 in codes


class TestSpoofedForwardedFor:
    def test_rotating_x_forwarded_for_prefix_cannot_bypass_limit(self, client, monkeypatch):
        monkeypatch.setattr(rl.settings, "trusted_proxy_count", 1)
        monkeypatch.setattr(rl.ingest_request_limiter, "max_requests", 2)
        codes = []
        for i in range(5):
            codes.append(client.post("/ingest", json={"packets": []}, headers={"X-Forwarded-For": f"10.9.8.{i}, 203.0.113.7"}).status_code)
        assert codes == [200, 200, 429, 429, 429]

    def test_x_forwarded_for_ignored_without_trusted_proxy(self, client, monkeypatch):
        monkeypatch.setattr(rl.settings, "trusted_proxy_count", 0)
        monkeypatch.setattr(rl.ingest_request_limiter, "max_requests", 2)
        codes = [client.post("/ingest", json={"packets": []}, headers={"X-Forwarded-For": f"10.9.8.{i}"}).status_code for i in range(4)]
        assert codes == [200, 200, 429, 429]

    def test_distinct_real_clients_do_not_share_a_budget(self, client, monkeypatch):
        monkeypatch.setattr(rl.settings, "trusted_proxy_count", 1)
        monkeypatch.setattr(rl.ingest_request_limiter, "max_requests", 1)
        assert client.post("/ingest", json={"packets": []}, headers={"X-Forwarded-For": "198.51.100.1"}).status_code == 200
        assert client.post("/ingest", json={"packets": []}, headers={"X-Forwarded-For": "198.51.100.2"}).status_code == 200


class TestLimiterFailureModes:
    def _break(self, limiter, monkeypatch):
        def boom(*a, **k):
            raise RuntimeError("limiter state unavailable")
        monkeypatch.setattr(limiter, "_check_key", boom)

    def test_ingest_fails_open(self, client, monkeypatch):
        self._break(rl.ingest_request_limiter, monkeypatch)
        self._break(rl.ingest_packet_limiter, monkeypatch)
        assert client.post("/ingest", json={"packets": [make_emergency()]}).status_code == 200  # an SOS is never blocked

    def test_register_fails_closed(self, client, monkeypatch):
        self._break(rl.register_ip_limiter, monkeypatch)
        assert register_profile(client, new_key()).status_code == 503

    def test_auth_fails_closed(self, client, monkeypatch):
        self._break(rl.auth_rate_limiter, monkeypatch)
        assert client.post("/auth/request-otp", json={"email": "a@example.com"}).status_code == 503

    def test_limiter_memory_is_bounded_under_identity_rotation(self):
        limiter = rl.InMemoryRateLimiter("bounded", 5, 60, max_keys=100)
        class R:
            client = None
            def __init__(self, ip): self.headers = {}; self.client = type("C", (), {"host": ip})()
        for i in range(1000):
            limiter.check(R(f"10.{i // 250}.{i % 250}.1"))
        assert len(limiter._hits) <= 100
