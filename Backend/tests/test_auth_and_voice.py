"""
Integration tests for Phase 5: email OTP auth (app/routers/auth.py) and
voice SOS ingest (app/routers/voice.py).

SMTP is never configured in this test environment (no SMTP_HOST/etc in
the test settings) -- by design. That means request-otp naturally
exercises the honest "delivered: false, here's why" path for free.

To test the actual VERIFY success path we still need the real plaintext
code, which the API deliberately never returns (see otp_service.py --
only the hash is stored). Tests that need a real code monkeypatch
app.services.otp_service.send_otp_email to capture the code as it's
generated and pretend delivery succeeded, which lets the test drive the
full request -> verify flow through the real HTTP endpoints rather than
reaching into internals.

Voice tests confirm the HONEST-FAILURE path: with openai-whisper not
installed in this test environment (it is a heavy optional dependency,
never assumed present), /ingest/voice/status must report unavailable
and POST /ingest/voice must return 503, not a crash and not a silent
fake-success.
"""
import io

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.main import app
from app.db.base import Base, get_db
import app.services.otp_service as otp_service


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
    test_client = TestClient(app)
    yield test_client
    app.dependency_overrides.clear()
    Base.metadata.drop_all(bind=engine)


def _capture_sent_code(monkeypatch):
    """
    Patches otp_service.send_otp_email (the name as imported into
    otp_service's own namespace -- patching the call site, not the
    definition site, matters for monkeypatch to take effect) to record
    the real plaintext code and report delivery success, without
    touching any actual SMTP server.
    """
    captured = {}

    def fake_send_otp_email(to_email, code, expiry_minutes):
        captured["code"] = code
        captured["email"] = to_email
        return True

    monkeypatch.setattr(otp_service, "send_otp_email", fake_send_otp_email)
    return captured


# ============================================================
# Email OTP auth
# ============================================================

class TestEmailOtp:
    def test_request_otp_honest_when_smtp_unconfigured(self, client):
        """
        Default test environment has no SMTP configured. The endpoint
        must return 200 with delivered=False and a clear explanation --
        never claim success over an email that didn't go out.
        """
        resp = client.post("/auth/request-otp", json={"email": "user@example.com"})
        assert resp.status_code == 200, resp.text
        body = resp.json()
        assert body["delivered"] is False
        assert "not configured" in body["detail"].lower() or "smtp" in body["detail"].lower()

    def test_full_request_and_verify_happy_path(self, client, monkeypatch):
        captured = _capture_sent_code(monkeypatch)

        req = client.post("/auth/request-otp", json={"email": "verify-me@example.com"})
        assert req.status_code == 200, req.text
        assert req.json()["delivered"] is True
        assert captured["email"] == "verify-me@example.com"

        verify = client.post(
            "/auth/verify-otp",
            json={"email": "verify-me@example.com", "code": captured["code"]},
        )
        assert verify.status_code == 200, verify.text
        body = verify.json()
        assert body["verified"] is True
        assert body["email"] == "verify-me@example.com"

    def test_code_is_single_use(self, client, monkeypatch):
        captured = _capture_sent_code(monkeypatch)
        client.post("/auth/request-otp", json={"email": "reuse@example.com"})

        first = client.post(
            "/auth/verify-otp", json={"email": "reuse@example.com", "code": captured["code"]}
        )
        assert first.status_code == 200

        second = client.post(
            "/auth/verify-otp", json={"email": "reuse@example.com", "code": captured["code"]}
        )
        assert second.status_code == 400
        assert "no active" in second.json()["detail"].lower()

    def test_incorrect_code_rejected_with_specific_reason(self, client, monkeypatch):
        _capture_sent_code(monkeypatch)
        client.post("/auth/request-otp", json={"email": "wrongcode@example.com"})

        resp = client.post(
            "/auth/verify-otp", json={"email": "wrongcode@example.com", "code": "000000"}
        )
        assert resp.status_code == 400
        assert "incorrect" in resp.json()["detail"].lower()

    def test_verify_with_no_prior_request_fails(self, client):
        resp = client.post(
            "/auth/verify-otp", json={"email": "never-requested@example.com", "code": "123456"}
        )
        assert resp.status_code == 400
        assert "no active" in resp.json()["detail"].lower()

    def test_too_many_attempts_locks_out_even_the_correct_code(self, client, monkeypatch):
        """
        MAX_OTP_ATTEMPTS is 5. After 5 wrong guesses, even the genuinely
        correct code must be rejected -- the attempt cap exists so a
        6-digit code (1 million combinations) can't be brute-forced.
        """
        captured = _capture_sent_code(monkeypatch)
        client.post("/auth/request-otp", json={"email": "bruteforce@example.com"})

        for _ in range(otp_service.MAX_OTP_ATTEMPTS):
            resp = client.post(
                "/auth/verify-otp",
                json={"email": "bruteforce@example.com", "code": "000000"},
            )
            assert resp.status_code == 400

        final = client.post(
            "/auth/verify-otp",
            json={"email": "bruteforce@example.com", "code": captured["code"]},
        )
        assert final.status_code == 400
        assert "too many" in final.json()["detail"].lower()

    def test_expired_code_rejected(self, client, monkeypatch):
        monkeypatch.setattr(otp_service, "OTP_EXPIRY_MINUTES", -1)
        captured = _capture_sent_code(monkeypatch)
        client.post("/auth/request-otp", json={"email": "expired@example.com"})

        resp = client.post(
            "/auth/verify-otp",
            json={"email": "expired@example.com", "code": captured["code"]},
        )
        assert resp.status_code == 400
        assert "expired" in resp.json()["detail"].lower()

    def test_resend_within_cooldown_reuses_existing_code(self, client, monkeypatch):
        captured = _capture_sent_code(monkeypatch)
        first = client.post("/auth/request-otp", json={"email": "cooldown@example.com"})
        assert first.status_code == 200
        first_code = captured["code"]

        second = client.post("/auth/request-otp", json={"email": "cooldown@example.com"})
        assert second.status_code == 200
        # Suppressed resend reuses the same code -- send_otp_email is not
        # called again, so captured["code"] still holds the FIRST code.
        assert captured["code"] == first_code

    def test_request_otp_rejects_malformed_email(self, client):
        resp = client.post("/auth/request-otp", json={"email": "not-an-email"})
        assert resp.status_code == 422


# ============================================================
# Voice SOS ingest -- honest-unavailable path
# (openai-whisper is a heavy optional dependency, never assumed
# installed in a test/CI environment)
# ============================================================

class TestVoiceIngest:
    def test_voice_status_reports_unavailable_without_whisper(self, client):
        resp = client.get("/ingest/voice/status")
        assert resp.status_code == 200, resp.text
        body = resp.json()
        assert body["available"] is False
        assert "whisper" in body["detail"].lower() or "ffmpeg" in body["detail"].lower()

    def test_voice_upload_returns_503_not_a_crash_when_unavailable(self, client):
        """
        The whole point of checking transcription_available() first in
        the router: a missing optional dependency must degrade to a
        clear 503, never a 500 or an unhandled exception.
        """
        fake_audio = io.BytesIO(b"not real audio data")
        resp = client.post(
            "/ingest/voice",
            files={"file": ("test.wav", fake_audio, "audio/wav")},
            data={"sender_id": "test-sender-hex", "latitude": "28.6", "longitude": "77.2"},
        )
        assert resp.status_code == 503
        assert "whisper" in resp.json()["detail"].lower()

    def test_voice_upload_rejects_unsupported_format(self, client):
        fake_file = io.BytesIO(b"not audio")
        resp = client.post(
            "/ingest/voice",
            files={"file": ("test.exe", fake_file, "application/octet-stream")},
            data={"sender_id": "test-sender-hex"},
        )
        # Whichever check runs first (availability vs format) is fine --
        # this must never be a 200 or a 500 either way.
        assert resp.status_code in (415, 503)

    def test_voice_upload_rejects_empty_file(self, client, monkeypatch):
        """
        Forces past the availability gate to specifically exercise the
        empty-file check underneath it.
        """
        import app.routers.voice as voice_router
        monkeypatch.setattr(voice_router, "transcription_available", lambda: True)

        empty_file = io.BytesIO(b"")
        resp = client.post(
            "/ingest/voice",
            files={"file": ("test.wav", empty_file, "audio/wav")},
            data={"sender_id": "test-sender-hex"},
        )
        assert resp.status_code == 400
        assert "empty" in resp.json()["detail"].lower()


# ============================================================
# Router registration sanity
# ============================================================

class TestRouterRegistration:
    """
    Regression guard: confirms every Phase 5 router is actually mounted
    on the app, not just importable. Catches the specific class of bug
    where a router module is written correctly but the include_router()
    call in main.py is missing or gets accidentally removed later.
    """

    def test_all_new_routes_are_registered(self):
        # openapi() is stable across FastAPI versions (app.routes may nest
        # _IncludedRouter objects without a .path on newer releases).
        registered_paths = set(app.openapi()["paths"].keys())
        expected = {
            "/auth/request-otp",
            "/auth/verify-otp",
            "/ingest/voice",
            "/ingest/voice/status",
            "/government/notifications",
            "/government/adapter-status",
            "/incidents/{incident_id}/government-notifications",
            "/alerts/nearby",
            "/alerts/{incident_id}/respond",
            "/incidents/{incident_id}/responses",
        }
        missing = expected - registered_paths
        assert not missing, f"Routes missing from app: {missing}"
