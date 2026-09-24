"""
Block 2 -- proof of possession (register), authenticated voice ingest,
authorised nearby alerts / respond, SMS idempotency.
"""

import json
import logging
import secrets
from datetime import datetime, timedelta, timezone

import pytest
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey

from app.core.rate_limit import ALL_LIMITERS
from app.models.incident import Incident, IncidentStatus
from app.models.signed_request_nonce import SignedRequestNonce
from app.models.sms_notification import SmsNotification
from app.models.user_profile import UserProfile
from tests.signing_helpers import (
    pubkey_hex,
    register_profile,
    sha,
    sign_request,
    signed_json_post,
    signed_nearby,
    signed_voice,
)
from tests.test_ingest import _pubkey_hex_for, _private_key_for, client, make_emergency  # noqa: F401
from tests.test_ingest_contract import db_session, ingest, only

WAV = b"RIFF\x24\x00\x00\x00WAVEfmt " + b"\x00" * 64


def new_key():
    return Ed25519PrivateKey.generate()


def iso(delta=0):
    return (datetime.now(timezone.utc) + timedelta(seconds=delta)).isoformat()


# ------------------------------------------------------------ registration PoP

class TestRegistrationProofOfPossession:
    def test_valid_pop_registers(self, client):
        key = new_key()
        resp = register_profile(client, key, name="Asha", contacts=["+91 98765 43210"])
        assert resp.status_code == 200, resp.text
        assert resp.json()["sender_id"] == pubkey_hex(key)
        assert db_session().query(UserProfile).count() == 1

    def test_unsigned_registration_is_refused(self, client):
        resp = client.post("/register", json={"sender_id": pubkey_hex(new_key()), "name": "X"})
        assert resp.status_code == 401
        assert db_session().query(UserProfile).count() == 0

    def test_invalid_signature(self, client):
        key = new_key()
        body = json.dumps({"sender_id": pubkey_hex(key), "name": "X", "emergency_contacts": []}).encode()
        headers = sign_request(key, "POST", "/register", [sha(body)])
        sig = headers["X-Setu-Signature"]
        headers["X-Setu-Signature"] = ("0" if sig[0] != "0" else "1") + sig[1:]
        resp = client.post("/register", content=body, headers={**headers, "Content-Type": "application/json"})
        assert resp.status_code == 401

    def test_wrong_key_cannot_register_someone_elses_sender_id(self, client):
        victim, attacker = new_key(), new_key()
        body = json.dumps({"sender_id": pubkey_hex(victim), "name": "Forged", "emergency_contacts": ["+919999999999"]}).encode()
        # attacker signs with their own key but claims the victim's identity in the header -> bad signature
        forged = sign_request(attacker, "POST", "/register", [sha(body)], sender=pubkey_hex(victim))
        assert client.post("/register", content=body, headers={**forged, "Content-Type": "application/json"}).status_code == 401
        # attacker authenticates as themselves but names the victim in the body -> identity mismatch
        honest = sign_request(attacker, "POST", "/register", [sha(body)])
        assert client.post("/register", content=body, headers={**honest, "Content-Type": "application/json"}).status_code == 403
        assert db_session().query(UserProfile).count() == 0

    def test_victim_profile_cannot_be_overwritten_by_someone_who_only_knows_the_public_key(self, client):
        victim = new_key()
        assert register_profile(client, victim, name="Real Name", contacts=["+911234567890"]).status_code == 200
        attacker = new_key()
        body = json.dumps({"sender_id": pubkey_hex(victim), "name": "Pwned", "emergency_contacts": ["+910000000000"]}).encode()
        for headers in (
            sign_request(attacker, "POST", "/register", [sha(body)]),
            sign_request(attacker, "POST", "/register", [sha(body)], sender=pubkey_hex(victim)),
        ):
            assert client.post("/register", content=body, headers={**headers, "Content-Type": "application/json"}).status_code in (401, 403)
        assert db_session().query(UserProfile).one().name == "Real Name"

    def test_reused_challenge_nonce_is_a_replay(self, client):
        key = new_key()
        nonce = secrets.token_hex(16)
        assert register_profile(client, key, nonce=nonce).status_code == 200
        replay = register_profile(client, key, nonce=nonce)
        assert replay.status_code == 401 and "replay" in replay.json()["detail"].lower()

    def test_captured_request_cannot_be_replayed_verbatim(self, client):
        key = new_key()
        body = json.dumps({"sender_id": pubkey_hex(key), "name": "A", "emergency_contacts": []}).encode()
        headers = {**sign_request(key, "POST", "/register", [sha(body)]), "Content-Type": "application/json"}
        assert client.post("/register", content=body, headers=headers).status_code == 200
        assert client.post("/register", content=body, headers=headers).status_code == 401

    @pytest.mark.parametrize("delta", [-3600, -301, 301, 3600])
    def test_expired_or_future_challenge(self, client, delta):
        assert register_profile(client, new_key(), timestamp=iso(delta)).status_code == 401

    def test_challenge_timestamp_inside_window_accepted(self, client):
        assert register_profile(client, new_key(), timestamp=iso(-250)).status_code == 200

    def test_tampered_body_after_signing(self, client):
        key = new_key()
        body = json.dumps({"sender_id": pubkey_hex(key), "name": "A", "emergency_contacts": []}).encode()
        headers = {**sign_request(key, "POST", "/register", [sha(body)]), "Content-Type": "application/json"}
        tampered = body.replace(b'"A"', b'"B"')
        assert client.post("/register", content=tampered, headers=headers).status_code == 401

    def test_signature_is_bound_to_the_path(self, client):
        key = new_key()
        body = json.dumps({"sender_id": pubkey_hex(key), "name": "A", "emergency_contacts": []}).encode()
        headers = {**sign_request(key, "POST", "/alerts/1/respond", [sha(body)]), "Content-Type": "application/json"}
        assert client.post("/register", content=body, headers=headers).status_code == 401

    def test_mesh_packet_signature_is_not_a_request_signature(self, client):
        """Domain separation: a valid packet signature can never authenticate a request."""
        key = _private_key_for("dev-x")
        packet = make_emergency(packet_id="ds1", emergency_id="e-ds1", sender_id="dev-x")
        body = json.dumps({"sender_id": pubkey_hex(key), "name": "A", "emergency_contacts": []}).encode()
        headers = {
            "X-Setu-Sender": pubkey_hex(key), "X-Setu-Timestamp": iso(), "X-Setu-Nonce": secrets.token_hex(16),
            "X-Setu-Signature": packet["signature"], "Content-Type": "application/json",
        }
        assert client.post("/register", content=body, headers=headers).status_code == 401

    @pytest.mark.parametrize("mutate,status", [
        ({"X-Setu-Sender": "not-hex"}, 400),
        ({"X-Setu-Sender": "AB" * 32}, 400),          # upper-case / non-canonical
        ({"X-Setu-Nonce": "short"}, 400),
        ({"X-Setu-Nonce": "bad nonce with spaces!!"}, 400),
        ({"X-Setu-Signature": "zz" * 64}, 400),
        ({"X-Setu-Signature": "00" * 10}, 400),
        ({"X-Setu-Timestamp": "yesterday"}, 400),
        ({"X-Setu-Timestamp": "2026-09-24T10:00:00"}, 400),  # naive
    ])
    def test_malformed_auth_headers(self, client, mutate, status):
        key = new_key()
        body = json.dumps({"sender_id": pubkey_hex(key), "name": "A", "emergency_contacts": []}).encode()
        headers = {**sign_request(key, "POST", "/register", [sha(body)]), **mutate, "Content-Type": "application/json"}
        resp = client.post("/register", content=body, headers=headers)
        assert resp.status_code == status, resp.text

    @pytest.mark.parametrize("payload", [
        {"sender_id": "", "name": "A"},
        {"name": "A"},
        {"sender_id": "x", "name": ""},
        {"sender_id": "x", "name": "A", "emergency_contacts": "not-a-list"},
        {"sender_id": "x", "name": "A", "age": -5},
        {"sender_id": "x", "name": "A", "emergency_contacts": ["call me maybe"]},
    ])
    def test_malformed_payload_is_422_not_500(self, client, payload):
        key = new_key()
        resp = signed_json_post(client, key, "/register", payload)
        assert resp.status_code == 422, resp.text

    def test_garbage_json_body_with_valid_signature_is_422(self, client):
        key = new_key()
        body = b"{not json"
        headers = {**sign_request(key, "POST", "/register", [sha(body)]), "Content-Type": "application/json"}
        resp = client.post("/register", content=body, headers=headers)
        assert resp.status_code == 422 and "Traceback" not in resp.text

    def test_nonces_are_only_consumed_by_authentic_requests(self, client):
        key = new_key()
        bad = sign_request(new_key(), "POST", "/register", ["x"], sender=pubkey_hex(key))
        client.post("/register", content=b"{}", headers={**bad, "Content-Type": "application/json"})
        assert db_session().query(SignedRequestNonce).count() == 0

    def test_old_nonces_are_pruned(self, client):
        db = db_session()
        db.add(SignedRequestNonce(sender_id="a" * 64, nonce="old" * 8, created_at=datetime.now(timezone.utc) - timedelta(hours=1)))
        db.commit()
        register_profile(client, new_key())
        assert db_session().query(SignedRequestNonce).filter(SignedRequestNonce.nonce == "old" * 8).count() == 0


# ------------------------------------------------------------ nearby alerts

def make_incident(db, lat=28.6139, lon=77.2090, n=1):
    for i in range(n):
        db.add(Incident(incident_type="fire", latitude=lat + i * 0.0001, longitude=lon, status=IncidentStatus.OPEN,
                        sender_priority="high", ai_priority=4.0))
    db.commit()


class TestNearbyAuthorization:
    P = {"lat": "28.6139", "lon": "77.209", "radius_km": "5"}

    def test_anonymous_cannot_enumerate(self, client):
        make_incident(db_session())
        resp = client.get("/alerts/nearby", params=self.P)
        assert resp.status_code == 401 and resp.json().get("detail")
        assert "incident_id" not in resp.text

    def test_signed_but_unregistered_is_forbidden(self, client):
        make_incident(db_session())
        assert signed_nearby(client, new_key(), self.P).status_code == 403

    def test_registered_device_gets_minimal_data(self, client):
        make_incident(db_session())
        key = new_key()
        register_profile(client, key)
        resp = signed_nearby(client, key, self.P)
        assert resp.status_code == 200
        row = resp.json()[0]
        assert set(row) == {"incident_id", "incident_type", "sender_priority", "ai_priority", "distance_km", "created_at", "message"}
        assert round(row["distance_km"], 1) == row["distance_km"]  # rounded to 100 m

    def test_no_pii_or_reporter_identity_leaks(self, client):
        reporter = new_key()
        register_profile(client, reporter, name="Secret Name", contacts=["+919876543210"])
        ingest(client, make_emergency(packet_id="pii1", emergency_id="e-pii", sender_id="dev-1"))
        viewer = new_key()
        register_profile(client, viewer)
        body = signed_nearby(client, viewer, self.P).text
        for secret_value in ("Secret Name", "9876543210", pubkey_hex(reporter), "medical", "sender_id", "emergency_contacts"):
            assert secret_value not in body

    def test_replay_is_refused(self, client):
        make_incident(db_session())
        key = new_key()
        register_profile(client, key)
        nonce = secrets.token_hex(16)
        assert signed_nearby(client, key, self.P, nonce=nonce).status_code == 200
        assert signed_nearby(client, key, self.P, nonce=nonce).status_code == 401

    def test_signature_binds_the_queried_location(self, client):
        """A captured request cannot be re-pointed at another location."""
        key = new_key()
        register_profile(client, key)
        headers = sign_request(key, "GET", "/alerts/nearby", ["28.6139", "77.209", "5"])
        resp = client.get("/alerts/nearby", params={"lat": "19.076", "lon": "72.8777", "radius_km": "5"}, headers=headers)
        assert resp.status_code == 401

    def test_sender_id_param_must_match_key(self, client):
        key = new_key()
        register_profile(client, key)
        resp = signed_nearby(client, key, {**self.P, "sender_id": pubkey_hex(new_key())})
        assert resp.status_code == 403

    def test_result_count_is_bounded(self, client):
        make_incident(db_session(), n=30)
        key = new_key()
        register_profile(client, key)
        assert len(signed_nearby(client, key, self.P).json()) == 20

    def test_per_sender_rate_limit(self, client):
        key = new_key()
        register_profile(client, key)
        statuses = [signed_nearby(client, key, self.P).status_code for _ in range(31)]
        assert statuses[:30] == [200] * 30 and statuses[30] == 429

    def test_closed_incidents_not_listed(self, client):
        db = db_session()
        make_incident(db)
        db.query(Incident).update({"status": IncidentStatus.CLOSED})
        db.commit()
        key = new_key()
        register_profile(client, key)
        assert signed_nearby(client, key, self.P).json() == []

    def test_respond_requires_signature_matching_sender_and_registration(self, client):
        make_incident(db_session())
        key, other = new_key(), new_key()
        payload = {"sender_id": pubkey_hex(key), "response_type": "CAN_HELP"}
        assert client.post("/alerts/1/respond", json=payload).status_code == 401
        assert signed_json_post(client, key, "/alerts/1/respond", payload).status_code == 403  # unregistered
        register_profile(client, key)
        assert signed_json_post(client, key, "/alerts/1/respond", payload).status_code == 200
        forged = {"sender_id": pubkey_hex(key), "response_type": "NEARBY"}
        assert signed_json_post(client, other, "/alerts/1/respond", forged).status_code == 403  # impersonation


# ------------------------------------------------------------ voice

@pytest.fixture()
def voice(client, monkeypatch):
    import app.routers.voice as voice_router
    monkeypatch.setattr(voice_router, "transcription_available", lambda: True)
    state = {"text": "Fire in the building, people trapped on the second floor"}
    monkeypatch.setattr(voice_router, "transcribe", lambda path: state["text"])
    return client, state, voice_router


class TestVoiceAuthentication:
    def test_signed_voice_creates_an_incident_for_the_authenticated_sender(self, voice):
        client, _, _ = voice
        key = new_key()
        resp = signed_voice(client, key, WAV)
        assert resp.status_code == 200, resp.text
        body = resp.json()
        assert body["incident_id"] and body["dedup_decision"] == "NEW_INCIDENT"
        from app.models.packet import RawPacket
        assert db_session().query(RawPacket).one().sender_id == pubkey_hex(key)

    def test_unsigned_voice_is_refused(self, voice):
        client, _, _ = voice
        resp = client.post("/ingest/voice", data={"sender_id": pubkey_hex(new_key())}, files={"file": ("a.wav", WAV, "audio/wav")})
        assert resp.status_code == 401
        assert db_session().query(Incident).count() == 0

    def test_form_sender_id_cannot_impersonate(self, voice):
        client, _, _ = voice
        attacker, victim = new_key(), new_key()
        register_profile(client, victim, name="Victim", contacts=["+911234567890"])
        resp = signed_voice(client, attacker, WAV, form_extra={"sender_id": pubkey_hex(victim)})
        assert resp.status_code == 403
        assert db_session().query(Incident).count() == 0
        assert db_session().query(SmsNotification).count() == 0  # no SMS to the victim's contacts

    def test_signature_binds_the_audio(self, voice):
        client, _, _ = voice
        key = new_key()
        headers = sign_request(key, "POST", "/ingest/voice", [sha(WAV), "28.6139", "77.2090", "", ""])
        other_audio = WAV + b"extra"
        resp = client.post("/ingest/voice", data={"latitude": "28.6139", "longitude": "77.2090"},
                           files={"file": ("a.wav", other_audio, "audio/wav")}, headers=headers)
        assert resp.status_code == 401

    def test_signature_binds_the_location(self, voice):
        client, _, _ = voice
        key = new_key()
        headers = sign_request(key, "POST", "/ingest/voice", [sha(WAV), "28.6139", "77.2090", "", ""])
        resp = client.post("/ingest/voice", data={"latitude": "10.0", "longitude": "10.0"},
                           files={"file": ("a.wav", WAV, "audio/wav")}, headers=headers)
        assert resp.status_code == 401

    def test_replayed_voice_request_refused(self, voice):
        client, _, _ = voice
        key = new_key()
        nonce = secrets.token_hex(16)
        assert signed_voice(client, key, WAV, nonce=nonce).status_code == 200
        assert signed_voice(client, key, WAV, nonce=nonce).status_code == 401

    def test_cannot_attach_voice_to_another_senders_emergency(self, voice):
        client, _, _ = voice
        ingest(client, make_emergency(packet_id="own1", emergency_id="victim-emergency", sender_id="dev-victim"))
        attacker = new_key()
        resp = signed_voice(client, attacker, WAV, emergency_id="victim-emergency")
        assert resp.status_code == 403

    def test_can_attach_voice_to_own_emergency(self, voice):
        client, _, _ = voice
        owner = _private_key_for("dev-owner")
        ingest(client, make_emergency(packet_id="own2", emergency_id="my-emergency", sender_id="dev-owner"))
        resp = signed_voice(client, owner, WAV, emergency_id="my-emergency")
        assert resp.status_code == 200 and resp.json()["emergency_id"] == "my-emergency"

    def test_unknown_emergency_id_is_refused(self, voice):
        client, _, _ = voice
        assert signed_voice(client, new_key(), WAV, emergency_id="made-up").status_code == 403

    @pytest.mark.parametrize("lat,lon", [("abc", "1"), ("91", "0"), ("0", "181"), ("nan", "0"), ("inf", "0")])
    def test_bad_coordinates_are_422(self, voice, lat, lon):
        client, _, _ = voice
        assert signed_voice(client, new_key(), WAV, lat=lat, lon=lon).status_code == 422

    def test_bad_priority_is_422(self, voice):
        client, _, _ = voice
        assert signed_voice(client, new_key(), WAV, priority="urgent!!").status_code == 422

    def test_file_validation(self, voice):
        client, _, vr = voice
        key = new_key()
        assert signed_voice(client, key, WAV, filename="a.exe").status_code == 415
        assert signed_voice(client, key, WAV, content_type="text/html").status_code == 415
        assert signed_voice(client, key, b"<html>not audio at all</html>").status_code == 415
        assert signed_voice(client, key, b"").status_code == 400
        assert signed_voice(client, key, WAV, filename="x" * 300 + ".wav").status_code == 422

    def test_oversized_audio_is_413_and_read_is_bounded(self, voice, monkeypatch):
        client, _, vr = voice
        monkeypatch.setattr(vr, "MAX_AUDIO_BYTES", 1000)
        assert signed_voice(client, new_key(), WAV + b"\0" * 2000).status_code == 413

    def test_very_long_transcript_does_not_500(self, voice):
        client, state, _ = voice
        state["text"] = "fire " * 2000
        resp = signed_voice(client, new_key(), WAV)
        assert resp.status_code == 200 and len(resp.json()["transcript"]) <= 2000

    def test_per_sender_voice_rate_limit(self, voice):
        client, _, _ = voice
        key = new_key()
        codes = [signed_voice(client, key, WAV).status_code for _ in range(6)]
        assert codes[:5] == [200] * 5 and codes[5] == 429

    def test_no_traceback_ever_reaches_the_client(self, voice):
        client, state, vr = voice
        for kwargs in ({"lat": "x"}, {"priority": "?"}, {"filename": "a.exe"}):
            resp = signed_voice(client, new_key(), WAV, **kwargs)
            assert resp.status_code < 500 and "Traceback" not in resp.text


# ------------------------------------------------------------ SMS idempotency

@pytest.fixture()
def sms(monkeypatch):
    import app.services.sms_service as sms_service
    sent = []
    outcome = {"ok": True}
    monkeypatch.setattr(sms_service, "send_sms", lambda number, message: sent.append(number) or outcome["ok"])
    return sent, outcome


class TestSmsIdempotency:
    def _setup(self, client, contacts):
        key = _private_key_for("dev-sms")
        assert register_profile(client, key, name="Sender", contacts=contacts).status_code == 200
        return make_emergency(packet_id="sms1", emergency_id="e-sms", sender_id="dev-sms")

    def test_one_sms_per_contact_on_new_incident(self, client, sms):
        sent, _ = sms
        packet = self._setup(client, ["+911111111111", "+922222222222"])
        entry = only(ingest(client, packet), "accepted")
        assert len(sent) == 2 and entry["sms_contacts_notified"] == 2

    def test_duplicate_upload_does_not_resend(self, client, sms):
        sent, _ = sms
        packet = self._setup(client, ["+911111111111"])
        ingest(client, packet)
        dup = only(ingest(client, packet), "duplicates")
        ingest(client, packet)
        assert len(sent) == 1 and dup["sms_contacts_notified"] == 1

    def test_retry_after_gateway_failure_resends_only_failed_contacts(self, client, sms):
        sent, outcome = sms
        packet = self._setup(client, ["+911111111111", "+922222222222"])
        outcome["ok"] = False
        first = only(ingest(client, packet), "accepted")
        assert first["sms_contacts_notified"] == 0 and len(sent) == 2
        outcome["ok"] = True
        retried = only(ingest(client, packet), "duplicates")  # client retry of the same packet
        assert len(sent) == 4 and retried["sms_contacts_notified"] == 2
        ingest(client, packet)
        assert len(sent) == 4  # settled: nothing more to send

    def test_merge_into_existing_incident_never_sends(self, client, sms):
        sent, _ = sms
        packet = self._setup(client, ["+911111111111"])
        ingest(client, packet)
        second = make_emergency(packet_id="sms2", emergency_id="e-sms2", sender_id="dev-sms")
        body = ingest(client, second)
        assert only(body, "accepted")["dedup_decision"] == "MERGED"
        assert len(sent) == 1

    def test_same_number_listed_twice_sends_once(self, client, sms):
        sent, _ = sms
        packet = self._setup(client, ["+91 98765 43210", "9876543210"])
        ingest(client, packet)
        assert len(sent) == 1

    def test_concurrent_claim_is_exclusive(self, client, sms):
        from app.services.sms_service import _claim, _contact_hash
        db = db_session()
        h = _contact_hash("+911111111111")
        assert _claim(db, "ev", h) is True
        assert _claim(db, "ev", h) is False  # in flight / queued: never a second owner

    def test_ledger_stores_no_phone_number_or_message(self, client, sms):
        packet = self._setup(client, ["+919876543210"])
        ingest(client, packet)
        for row in db_session().query(SmsNotification).all():
            assert "9876543210" not in json.dumps({c.name: str(getattr(row, c.name)) for c in row.__table__.columns})

    def test_logs_never_contain_full_number_or_body(self, client, monkeypatch, caplog):
        import app.services.sms_service as sms_service
        monkeypatch.setattr(sms_service.settings, "sms_gateway_username", "")
        packet = self._setup(client, ["+919876543210"])
        with caplog.at_level(logging.DEBUG):
            ingest(client, packet)
        assert "9876543210" not in caplog.text
        assert "SETU Alert" not in caplog.text
        assert "reported a" not in caplog.text

    def test_no_profile_no_contacts_no_sms(self, client, sms):
        sent, _ = sms
        entry = only(ingest(client, make_emergency(packet_id="np1", emergency_id="e-np")), "accepted")
        assert sent == [] and entry["sms_contacts_notified"] == 0
