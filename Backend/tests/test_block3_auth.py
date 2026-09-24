"""
Block 3 -- authentication / authorization hardening.

* dashboard sessions (no responder key in the browser)
* ADMIN vs RESPONDER separation, responder trust (revoke, empty registry, restart)
* CORS explicitness, endpoint classification gate
"""

import base64
import json
import time

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from app.core.config import settings
from app.main import app
from app.services import session_service
from app.services.session_service import issue_token, verify_token
from tests.conftest import TEST_ADMIN_KEY, TEST_SESSION_SECRET
from tests.signing_helpers import register_profile
from tests.test_ingest import _pubkey_hex_for, client, make_emergency, make_termination, register_responder  # noqa: F401
from tests.test_ingest_contract import db_session, ingest, only
from tests.test_request_auth import new_key

RESPONDER_KEY = "test-responder-api-key"
A = {"x-api-key": TEST_ADMIN_KEY}


@pytest.fixture()
def api(client):
    original = settings.responder_api_key
    settings.responder_api_key = RESPONDER_KEY
    yield client
    settings.responder_api_key = original


def login(client, key=RESPONDER_KEY):
    return client.post("/auth/responder-login", json={"key": key})


def bearer(token):
    return {"Authorization": f"Bearer {token}"}


def forge(claims, secret=TEST_SESSION_SECRET):
    import hashlib, hmac
    b = lambda d: base64.urlsafe_b64encode(d).rstrip(b"=").decode()
    part = b(json.dumps(claims, separators=(",", ":")).encode())
    sig = b(hmac.new(secret.encode(), part.encode(), hashlib.sha256).digest())
    return f"{part}.{sig}"


# ------------------------------------------------------------------ sessions

class TestDashboardSessions:
    def test_login_returns_bounded_token_and_never_the_key(self, api):
        resp = login(api)
        assert resp.status_code == 200
        body = resp.json()
        assert body["token_type"] == "Bearer" and body["expires_in"] == settings.session_ttl_seconds
        assert RESPONDER_KEY not in resp.text and TEST_ADMIN_KEY not in resp.text
        assert "set-cookie" not in {k.lower() for k in resp.headers}

    def test_token_reads_incidents_and_resolves(self, api):
        token = login(api).json()["access_token"]
        ingest(api, make_emergency(packet_id="s1", emergency_id="e-s1"))
        assert api.get("/incidents", headers=bearer(token)).status_code == 200
        resolved = api.post("/incidents/1/resolve", headers=bearer(token))
        assert resolved.status_code == 200 and resolved.json()["status"] == "CLOSED"
        from app.models.audit_log import IncidentAuditLog
        detail = db_session().query(IncidentAuditLog).order_by(IncidentAuditLog.id.desc()).first().detail
        assert "session" in detail and token not in detail  # accountable, without leaking the token

    def test_wrong_key_is_401_and_damped(self, api):
        assert login(api, "wrong").status_code == 401
        codes = [login(api, f"guess{i}").status_code for i in range(25)]
        assert 429 in codes

    def test_login_refuses_the_admin_key_and_empty_key(self, api):
        assert login(api, TEST_ADMIN_KEY).status_code == 401
        assert api.post("/auth/responder-login", json={"key": ""}).status_code == 422
        assert api.post("/auth/responder-login", json={}).status_code == 422

    @pytest.mark.parametrize("bad", [
        "", "garbage", "a.b", "a.b.c", "x" * 2000, "Bearer",
    ])
    def test_invalid_tokens_are_401(self, api, bad):
        assert api.get("/incidents", headers={"Authorization": f"Bearer {bad}"}).status_code == 401

    def test_expired_token(self, api):
        now = int(time.time())
        token = forge({"v": 1, "role": "responder", "iat": now - 7200, "exp": now - 3600, "jti": "x"})
        assert api.get("/incidents", headers=bearer(token)).status_code == 401
        assert verify_token(token) is None

    def test_token_signed_with_another_secret_or_tampered(self, api):
        now = int(time.time())
        claims = {"v": 1, "role": "responder", "iat": now, "exp": now + 600, "jti": "x"}
        assert api.get("/incidents", headers=bearer(forge(claims, secret="another-secret-" + "x" * 30))).status_code == 401
        good = login(api).json()["access_token"]
        part, sig = good.split(".")
        other = base64.urlsafe_b64encode(json.dumps({**claims, "role": "admin"}).encode()).rstrip(b"=").decode()
        assert api.get("/incidents", headers=bearer(f"{other}.{sig}")).status_code == 401  # role escalation
        assert api.get("/incidents", headers=bearer(f"{part}.{sig[:-2]}AA")).status_code == 401

    def test_admin_role_claim_is_not_accepted(self, api):
        now = int(time.time())
        token = forge({"v": 1, "role": "admin", "iat": now, "exp": now + 600, "jti": "x"})  # correctly signed!
        assert api.get("/incidents", headers=bearer(token)).status_code == 401

    def test_future_dated_and_wrong_version_tokens(self, api):
        now = int(time.time())
        assert verify_token(forge({"v": 1, "role": "responder", "iat": now + 3600, "exp": now + 9000, "jti": "x"})) is None
        assert verify_token(forge({"v": 2, "role": "responder", "iat": now, "exp": now + 600, "jti": "x"})) is None

    def test_session_token_cannot_provision_or_revoke_responders(self, api):
        token = login(api).json()["access_token"]
        body = {"public_key": _pubkey_hex_for("self-promote"), "name": "me"}
        assert api.post("/responders", json=body, headers=bearer(token)).status_code == 401
        assert api.post("/responders", json=body, headers={"x-api-key": RESPONDER_KEY}).status_code == 401  # responder key is not admin
        assert api.get("/responders/keys").json() == {"responder_public_keys": []}

    def test_sessions_disabled_without_secret_or_with_short_secret(self, api):
        settings.session_secret = ""
        assert login(api).status_code == 503
        settings.session_secret = "too-short"
        assert login(api).status_code == 503
        assert verify_token("a.b") is None

    def test_default_placeholder_key_cannot_login_in_production(self, api):
        settings.debug = False
        settings.responder_api_key = "changeme-dev-key"
        assert login(api, "changeme-dev-key").status_code == 500

    def test_legacy_header_key_still_works_for_server_side_tools(self, api):
        assert api.get("/incidents", headers={"x-api-key": RESPONDER_KEY}).status_code == 200
        assert api.get("/incidents").status_code == 401


# ------------------------------------------------------------------ responder trust

class TestResponderTrust:
    def test_only_admin_can_provision(self, api):
        good = {"public_key": _pubkey_hex_for("r1"), "name": "R1"}
        assert api.post("/responders", json=good).status_code == 401
        assert api.post("/responders", json=good, headers={"x-api-key": "nope"}).status_code == 401
        assert api.post("/responders", json=good, headers=A).status_code == 200

    def test_admin_fails_closed_when_unconfigured(self, api):
        settings.admin_api_key = ""
        settings.debug = False
        assert api.post("/responders", json={"public_key": _pubkey_hex_for("r1"), "name": "R"}, headers={"x-api-key": RESPONDER_KEY}).status_code == 503

    @pytest.mark.parametrize("key", ["responder-device-1", "AB" * 32, "0" * 63, "g" * 64, "0" * 65, ""])
    def test_responder_identity_must_be_a_ed25519_hex_key(self, api, key):
        assert api.post("/responders", json={"public_key": key, "name": "R"}, headers=A).status_code == 422

    def test_authorized_unauthorized_unknown_and_empty_registry(self, api):
        ingest(api, make_emergency(packet_id="e1", emergency_id="tr-1"))
        # EMPTY registry: fail closed
        assert only(ingest(api, make_termination(packet_id="t0", emergency_id="tr-1", sender_id="rA")), "rejected")["code"] == "unauthorized_responder"
        register_responder(api, public_key=_pubkey_hex_for("rB"))
        # unknown key (registry non-empty, sender not in it)
        assert only(ingest(api, make_termination(packet_id="t1", emergency_id="tr-1", sender_id="rA")), "rejected")["code"] == "unauthorized_responder"
        # citizen key that reported the emergency is not a responder
        assert only(ingest(api, make_termination(packet_id="t2", emergency_id="tr-1", sender_id="dev-1")), "rejected")["code"] == "unauthorized_responder"
        assert db_session().query(__import__("app.models.incident", fromlist=["Incident"]).Incident).one().status.value == "OPEN"
        # authorized
        assert only(ingest(api, make_termination(packet_id="t3", emergency_id="tr-1", sender_id="rB")), "accepted")["closed_incident_id"] == 1

    def test_responder_id_field_is_never_used_for_authorization(self, api):
        register_responder(api, public_key=_pubkey_hex_for("rB"))
        ingest(api, make_emergency(packet_id="e1", emergency_id="tr-2"))
        forged = make_termination(packet_id="t1", emergency_id="tr-2", sender_id="attacker", responder_id=_pubkey_hex_for("rB"))
        assert only(ingest(api, forged), "rejected")["code"] == "unauthorized_responder"

    def test_forged_termination_signature_is_rejected_before_authorization(self, api):
        register_responder(api, public_key=_pubkey_hex_for("rB"))
        ingest(api, make_emergency(packet_id="e1", emergency_id="tr-3"))
        forged = make_termination(packet_id="t1", emergency_id="tr-3", sender_id="rB")
        forged["emergency_id"] = "other"  # tamper after signing
        assert only(ingest(api, forged), "rejected")["code"] == "invalid_signature"

    def test_revoked_responder_loses_authority_immediately_and_drops_from_keys(self, api):
        key = _pubkey_hex_for("rB")
        register_responder(api, public_key=key)
        assert api.get("/responders/keys").json() == {"responder_public_keys": [key]}
        ingest(api, make_emergency(packet_id="e1", emergency_id="tr-4"))
        assert api.post(f"/responders/{key}/revoke").status_code == 401
        assert api.post(f"/responders/{key}/revoke", headers={"x-api-key": RESPONDER_KEY}).status_code == 401
        assert api.post(f"/responders/{key}/revoke", headers=A).status_code == 200
        assert api.get("/responders/keys").json() == {"responder_public_keys": []}
        assert only(ingest(api, make_termination(packet_id="t1", emergency_id="tr-4", sender_id="rB")), "rejected")["code"] == "unauthorized_responder"
        assert api.post("/responders/" + "0" * 64 + "/revoke", headers=A).status_code == 404

    def test_trusted_registry_survives_a_process_restart(self, tmp_path):
        """Persistence: a brand-new engine/session over the same database still sees the responder."""
        from app.db.base import Base
        from app.models.responder import ResponderProfile
        from app.services.responder_service import is_authorized_responder
        url = f"sqlite:///{tmp_path / 'reg.db'}"
        key = _pubkey_hex_for("rB")
        first = create_engine(url)
        Base.metadata.create_all(first)
        with sessionmaker(bind=first)() as db:
            db.add(ResponderProfile(public_key=key, name="R"))
            db.commit()
        first.dispose()  # "restart"
        second = create_engine(url)
        with sessionmaker(bind=second)() as db:
            assert is_authorized_responder(db, key) is True
            assert is_authorized_responder(db, _pubkey_hex_for("stranger")) is False
            assert is_authorized_responder(db, None) is False and is_authorized_responder(db, "") is False

    def test_close_by_emergency_id_uses_equality_not_patterns(self, api):
        register_responder(api, public_key=_pubkey_hex_for("rB"))
        ingest(api, make_emergency(packet_id="e1", emergency_id="abc-1"))
        for wildcard in ("%", "_", "abc-%", "a_c-1", "*"):
            entry = only(ingest(api, make_termination(packet_id=f"w{abs(hash(wildcard))}", emergency_id=wildcard, sender_id="rB")), "accepted")
            assert entry["closed_incident_id"] is None
        from app.models.incident import Incident, IncidentStatus
        assert db_session().query(Incident).one().status == IncidentStatus.OPEN


# ------------------------------------------------------------------ CORS

class TestCors:
    DASH = "https://setu-sih-dashboard.vercel.app"

    def preflight(self, client, origin, method="GET", headers="authorization"):
        return client.options("/incidents", headers={"Origin": origin, "Access-Control-Request-Method": method, "Access-Control-Request-Headers": headers})

    def test_allowed_origin_preflight(self, client):
        r = self.preflight(client, self.DASH)
        assert r.status_code == 200
        assert r.headers["access-control-allow-origin"] == self.DASH
        assert "access-control-allow-credentials" not in r.headers
        assert "authorization" in r.headers["access-control-allow-headers"].lower()

    def test_unknown_origin_gets_no_cors_grant(self, client):
        for origin in ("https://evil.example", "http://localhost:5173", "https://setu-sih-dashboard.vercel.app.evil.example", "null"):
            r = self.preflight(client, origin)
            assert r.status_code == 400
            assert "access-control-allow-origin" not in r.headers

    def test_never_wildcard(self, client):
        for origin in (self.DASH, "https://evil.example"):
            r = client.get("/health", headers={"Origin": origin})
            assert r.headers.get("access-control-allow-origin") != "*"

    def test_disallowed_method_and_header_are_refused(self, client):
        assert self.preflight(client, self.DASH, method="DELETE").status_code == 400
        assert self.preflight(client, self.DASH, headers="x-evil-header").status_code == 400

    def test_wildcard_env_value_is_ignored_and_localhost_only_in_debug(self):
        from app.core.config import Settings
        s = Settings(_env_file=None, cors_allowed_origins_raw="*, https://a.example/", debug=False)
        assert s.cors_allowed_origins == ["https://a.example"]
        assert "http://localhost:5173" not in s.cors_allowed_origins
        assert "http://localhost:5173" in Settings(_env_file=None, debug=True).cors_allowed_origins

    def test_mobile_requests_without_origin_are_unaffected(self, client):
        assert client.post("/ingest", json={"packets": [make_emergency()]}).status_code == 200
        assert client.get("/responders/keys").status_code == 200


# ------------------------------------------------------------------ production config self-check

class TestStartupChecks:
    def test_flags_every_required_production_setting(self, monkeypatch):
        from app.core.startup_checks import production_config_findings
        monkeypatch.setattr(settings, "debug", False)
        monkeypatch.setattr(settings, "responder_api_key", "changeme-dev-key")
        monkeypatch.setattr(settings, "admin_api_key", "")
        monkeypatch.setattr(settings, "session_secret", "short")
        monkeypatch.delenv("TRUSTED_PROXY_COUNT", raising=False)
        text = " | ".join(production_config_findings())
        for needle in ("RESPONDER_API_KEY", "ADMIN_API_KEY", "SESSION_SECRET", "TRUSTED_PROXY_COUNT", "PostgreSQL"):
            assert needle in text
        assert "changeme-dev-key" not in text  # names only, never values

    def test_clean_configuration_has_no_findings_except_database(self, monkeypatch):
        from app.core.startup_checks import production_config_findings
        monkeypatch.setattr(settings, "debug", False)
        monkeypatch.setattr(settings, "responder_api_key", "r" * 40)
        monkeypatch.setattr(settings, "admin_api_key", "a" * 40)
        monkeypatch.setattr(settings, "session_secret", "s" * 40)
        monkeypatch.setattr(settings, "database_url", "postgresql+psycopg2://u:p@h/db")
        monkeypatch.setenv("TRUSTED_PROXY_COUNT", "1")
        assert production_config_findings() == []

    def test_admin_equal_to_responder_key_is_flagged(self, monkeypatch):
        from app.core.startup_checks import production_config_findings
        monkeypatch.setattr(settings, "debug", False)
        monkeypatch.setattr(settings, "responder_api_key", "k" * 40)
        monkeypatch.setattr(settings, "admin_api_key", "k" * 40)
        assert any("promote" in f for f in production_config_findings())
