"""
Integration tests for Phase 5: email OTP auth (app/routers/auth.py) and
voice SOS ingest (app/routers/voice.py).

Email OTP is DEMO-ONLY: this server has no email provider. request-otp
returns the generated code as demo_code (with demo_mode=True,
delivered=False) and verify-otp checks it against the stored hash.

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


def _request(client, email):
    return client.post("/auth/request-otp", json={"email": email})


def _verify(client, email, code):
    return client.post("/auth/verify-otp", json={"email": email, "code": code})


# ============================================================
# Email OTP auth -- DEMO mode (no email is ever sent)
# ============================================================

class TestDemoEmailOtp:
    def test_request_returns_marked_demo_code_and_never_claims_delivery(self, client):
        resp = _request(client, "user@example.com")
        assert resp.status_code == 200, resp.text
        body = resp.json()
        assert body["demo_mode"] is True
        assert body["delivered"] is False
        assert len(body["demo_code"]) == 6 and body["demo_code"].isdigit()
        assert "demo" in body["detail"].lower()
        assert "smtp" not in body["detail"].lower()
        assert "not configured" not in body["detail"].lower()

    def test_codes_are_random_not_a_fixed_value(self, client):
        codes = {_request(client, f"u{i}@example.com").json()["demo_code"] for i in range(8)}
        assert len(codes) > 1

    def test_only_a_hash_is_stored(self, client):
        code = _request(client, "hash@example.com").json()["demo_code"]
        from app.models.email_otp import EmailOtp
        db = next(app.dependency_overrides[get_db]())
        try:
            row = db.query(EmailOtp).filter_by(email="hash@example.com").one()
            assert row.code_hash != code and code not in row.code_hash
            assert row.delivered is False
        finally:
            db.close()

    def test_correct_code_verifies_and_is_single_use(self, client):
        code = _request(client, "ok@example.com").json()["demo_code"]
        ok = _verify(client, "ok@example.com", code)
        assert ok.status_code == 200, ok.text
        assert ok.json()["verified"] is True
        assert ok.json()["email"] == "ok@example.com"
        again = _verify(client, "ok@example.com", code)
        assert again.status_code == 400
        assert "no active" in again.json()["detail"].lower()

    def test_wrong_code_rejected(self, client):
        code = _request(client, "wrong@example.com").json()["demo_code"]
        wrong = "000000" if code != "000000" else "111111"
        resp = _verify(client, "wrong@example.com", wrong)
        assert resp.status_code == 400
        assert "incorrect" in resp.json()["detail"].lower()

    def test_verify_with_no_prior_request_fails(self, client):
        resp = _verify(client, "never-requested@example.com", "123456")
        assert resp.status_code == 400
        assert "no active" in resp.json()["detail"].lower()

    def test_expired_code_rejected(self, client, monkeypatch):
        monkeypatch.setattr(otp_service, "OTP_EXPIRY_MINUTES", -1)
        code = _request(client, "expired@example.com").json()["demo_code"]
        resp = _verify(client, "expired@example.com", code)
        assert resp.status_code == 400
        assert "expired" in resp.json()["detail"].lower()

    def test_too_many_attempts_locks_out_even_the_correct_code(self, client):
        code = _request(client, "brute@example.com").json()["demo_code"]
        wrong = "000000" if code != "000000" else "111111"
        for _ in range(otp_service.MAX_OTP_ATTEMPTS):
            assert _verify(client, "brute@example.com", wrong).status_code == 400
        final = _verify(client, "brute@example.com", code)
        assert final.status_code == 400
        assert "too many" in final.json()["detail"].lower()

    def test_resend_within_cooldown_is_rejected(self, client):
        assert _request(client, "cool@example.com").status_code == 200
        second = _request(client, "cool@example.com")
        assert second.status_code == 429
        assert "retry-after" in {k.lower() for k in second.headers}
        assert second.json().get("demo_code") is None

    def test_resend_after_cooldown_issues_fresh_code_and_voids_old(self, client, monkeypatch):
        first = _request(client, "again@example.com").json()["demo_code"]
        monkeypatch.setattr(otp_service, "RESEND_COOLDOWN_SECONDS", 0)
        second = _request(client, "again@example.com")
        assert second.status_code == 200
        new_code = second.json()["demo_code"]
        if new_code != first:
            assert _verify(client, "again@example.com", first).status_code == 400
        assert _verify(client, "again@example.com", new_code).status_code == 200

    def test_request_rejects_malformed_email(self, client):
        assert _request(client, "not-an-email").status_code == 422

    def test_no_smtp_or_email_provider_dependency(self):
        import importlib.util
        import app.core.config as cfg
        assert importlib.util.find_spec("app.services.email_service") is None
        assert not [f for f in cfg.Settings.model_fields if f.startswith("smtp")]
        assert not hasattr(otp_service, "send_otp_email")


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
        registered_paths = {route.path for route in app.routes}
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
