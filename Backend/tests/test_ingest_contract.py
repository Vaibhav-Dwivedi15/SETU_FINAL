"""
Block 2 -- /ingest outcome semantics, packet identity (packet-ID squatting),
timestamp / expiry contract.

Invariant under test: HTTP success != packet acceptance. Every packet lands in
exactly one of accepted / duplicates / rejected / failed.
"""

import json
from datetime import datetime, timedelta, timezone

import pytest
from sqlalchemy import create_engine, inspect, text

from app.core import contract
from app.core.timeutil import parse_timestamp
from app.db.base import get_db
from app.db.init_db import upgrade_raw_packet_identity
from app.main import app
from app.models.packet import PacketStatus, RawPacket, RejectedPacket
from tests.test_ingest import (  # noqa: F401  (client is a fixture)
    _pubkey_hex_for,
    _sign_packet,
    client,
    make_emergency,
    make_termination,
    register_responder,
)


def ingest(client, *packets):
    resp = client.post("/ingest", json={"packets": list(packets)})
    assert resp.status_code == 200, resp.text
    return resp.json()


def ts(delta_seconds=0, fmt=None):
    moment = datetime.now(timezone.utc) + timedelta(seconds=delta_seconds)
    if fmt == "z6":
        return moment.strftime("%Y-%m-%dT%H:%M:%S.%f") + "Z"  # Dart toIso8601String with micros
    if fmt == "z3":
        return moment.strftime("%Y-%m-%dT%H:%M:%S.") + f"{moment.microsecond // 1000:03d}Z"
    if fmt == "z0":
        return moment.strftime("%Y-%m-%dT%H:%M:%S") + "Z"
    if fmt == "ist":
        return moment.astimezone(timezone(timedelta(hours=5, minutes=30))).isoformat()
    return moment.isoformat()


def only(body, bucket):
    assert len(body[bucket]) == 1, body
    return body[bucket][0]


def db_session():
    return next(app.dependency_overrides[get_db]())


def assert_exactly_one_state(body, packet_id, expected_bucket):
    found = [b for b in ("accepted", "duplicates", "rejected", "failed") if any(e["packet_id"] == packet_id for e in body[b])]
    assert found == [expected_bucket], (found, body)


# ---------------------------------------------------------------- Phase 1

class TestIngestOutcomes:
    def test_accepted(self, client):
        body = ingest(client, make_emergency(packet_id="a1", emergency_id="e-a1"))
        entry = only(body, "accepted")
        assert entry["packet_id"] == "a1" and entry["status"] == "ACCEPTED"
        assert entry["incident_id"] is not None
        assert entry["dedup_decision"] == "NEW_INCIDENT"
        assert body["duplicates"] == body["rejected"] == body["failed"] == []

    def test_duplicate_is_its_own_state_not_a_rejection(self, client):
        packet = make_emergency(packet_id="d1", emergency_id="e-d1")
        first = only(ingest(client, packet), "accepted")
        body = ingest(client, packet)
        entry = only(body, "duplicates")
        assert entry["status"] == "DUPLICATE" and entry["packet_id"] == "d1"
        assert entry["incident_id"] == first["incident_id"]
        assert body["accepted"] == body["rejected"] == body["failed"] == []

    def test_invalid_signature_rejected_with_http_200(self, client):
        packet = make_emergency(packet_id="s1", emergency_id="e-s1")
        packet["message"] = "tampered after signing"
        resp = client.post("/ingest", json={"packets": [packet]})
        assert resp.status_code == 200  # HTTP success != acceptance
        entry = only(resp.json(), "rejected")
        assert entry["code"] == "invalid_signature" and entry["status"] == "REJECTED"
        assert resp.json()["accepted"] == []

    def test_stale_packet_rejected(self, client):
        entry = only(ingest(client, make_emergency(packet_id="st1", emergency_id="e-st", timestamp=ts(-7200))), "rejected")
        assert entry["code"] == "stale"

    def test_invalid_ttl_rejected(self, client):
        for ttl, pid in ((9, "ttl9"), (0, "ttl0"), (-1, "ttlneg")):
            packet = make_emergency(packet_id=pid, emergency_id=f"e-{pid}")
            packet["ttl"] = ttl  # ttl is not signed, so the signature stays valid
            entry = only(ingest(client, packet), "rejected")
            assert entry["code"] == "invalid_ttl", (ttl, entry)

    def test_malformed_packets_rejected_individually(self, client):
        good = make_emergency(packet_id="g1", emergency_id="e-g1")
        body = ingest(client, "garbage", 42, None, {"packet_id": "only-id"}, [], good)
        assert [e["packet_id"] for e in body["accepted"]] == ["g1"]
        assert len(body["rejected"]) == 5
        codes = {e["code"] for e in body["rejected"]}
        assert "malformed" in codes
        assert all(e["status"] == "REJECTED" for e in body["rejected"])

    def test_missing_required_field_rejected(self, client):
        packet = make_emergency(packet_id="m1", emergency_id="e-m1")
        del packet["nonce"]
        entry = only(ingest(client, packet), "rejected")
        assert entry["code"] == "schema" and entry["packet_id"] == "m1"

    def test_oversized_packet_rejected(self, client):
        packet = make_emergency(packet_id="big1", emergency_id="e-big")
        packet["message"] = "🔥" * 2000  # 2000 chars (schema-legal) but 8000 UTF-8 bytes
        entry = only(ingest(client, packet), "rejected")
        assert entry["code"] == "too_large"

    def test_unknown_and_mesh_only_packet_types_rejected(self, client):
        base = make_emergency(packet_id="t1", emergency_id="e-t1")
        for ptype, code in (("bogus", "unknown_type"), ("ack", "unsupported_type"), ("alert", "unsupported_type"), (None, "unknown_type"), (7, "unknown_type")):
            packet = dict(base, packet_id=f"t-{ptype}", type=ptype)
            entry = only(ingest(client, packet), "rejected")
            assert entry["code"] == code, (ptype, entry)

    def test_rejected_packets_are_never_stored_as_accepted_evidence(self, client):
        ingest(client, make_emergency(packet_id="ns1", emergency_id="e-ns", timestamp=ts(-7200)))
        db = db_session()
        assert db.query(RawPacket).count() == 0
        assert db.query(RejectedPacket).filter(RejectedPacket.packet_id == "ns1").count() == 1

    def test_unauthorized_termination_rejected_and_retryable_after_registration(self, client):
        ingest(client, make_emergency(packet_id="ue1", emergency_id="e-ue"))
        term = make_termination(packet_id="ut1", emergency_id="e-ue", sender_id="late-responder")
        assert only(ingest(client, term), "rejected")["code"] == "unauthorized_responder"
        register_responder(client, public_key=_pubkey_hex_for("late-responder"))
        assert only(ingest(client, term), "accepted")["closed_incident_id"] is not None

    def test_every_packet_reported_exactly_once(self, client):
        a = make_emergency(packet_id="x1", emergency_id="e-x1")
        b = make_emergency(packet_id="x2", emergency_id="e-x2", timestamp=ts(-7200))
        body = ingest(client, a, a, b)
        assert_exactly_one_state(body, "x2", "rejected")
        assert len(body["accepted"]) == 1 and len(body["duplicates"]) == 1

    def test_ack_packet_type_is_never_accepted_or_stored(self, client):
        ack = make_emergency(packet_id="ack-1", emergency_id="e-ack")
        ack["type"] = "ack"
        ack["original_packet_id"] = "x"
        entry = only(ingest(client, ack), "rejected")
        assert entry["code"] == "unsupported_type"
        assert db_session().query(RawPacket).count() == 0

    def test_batch_over_500_is_a_whole_request_error(self, client):
        resp = client.post("/ingest", json={"packets": [{}] * 501})
        assert resp.status_code == 422

    def test_unparseable_body_is_controlled_4xx(self, client):
        resp = client.post("/ingest", content=b"{not json", headers={"Content-Type": "application/json"})
        assert resp.status_code == 422
        assert "Traceback" not in resp.text


# ---------------------------------------------------------------- Phase 2

class TestPacketIdSquatting:
    def test_1_first_valid_packet(self, client):
        assert only(ingest(client, make_emergency(packet_id="sq", emergency_id="e-sq", sender_id="victim")), "accepted")

    def test_2_exact_duplicate(self, client):
        p = make_emergency(packet_id="sq", emergency_id="e-sq", sender_id="victim")
        ingest(client, p)
        assert only(ingest(client, p), "duplicates")["status"] == "DUPLICATE"

    def test_3_same_packet_id_different_sender_is_independent(self, client):
        attacker = make_emergency(packet_id="sq", emergency_id="e-atk", sender_id="attacker")
        victim = make_emergency(packet_id="sq", emergency_id="e-vic", sender_id="victim")
        ingest(client, attacker)
        body = ingest(client, victim)
        assert only(body, "accepted")["packet_id"] == "sq"  # NOT suppressed as duplicate
        assert body["duplicates"] == []

    def test_4_same_packet_id_different_payload_same_sender_is_a_conflict_not_a_duplicate(self, client):
        ingest(client, make_emergency(packet_id="sq", emergency_id="e-1", sender_id="victim"))
        changed = make_emergency(packet_id="sq", emergency_id="e-2", sender_id="victim")
        body = ingest(client, changed)
        entry = only(body, "rejected")
        assert entry["code"] == "packet_id_conflict"
        assert body["duplicates"] == []  # must never look "delivered"

    def test_5_same_packet_id_invalid_signature_does_not_touch_the_original(self, client):
        genuine = make_emergency(packet_id="sq", emergency_id="e-sq", sender_id="victim")
        ingest(client, genuine)
        forged = dict(genuine, message="forged", signature=genuine["signature"])
        assert only(ingest(client, forged), "rejected")["code"] == "invalid_signature"
        # ...and the genuine packet is still recognised as its own duplicate.
        assert only(ingest(client, genuine), "duplicates")

    def test_6_legitimate_packet_after_malicious_collision(self, client):
        genuine = make_emergency(packet_id="sq", emergency_id="e-sq", sender_id="victim")
        forged_unsigned = dict(genuine, signature="00" * 64, message="squat")
        stale_forged = make_emergency(packet_id="sq", emergency_id="e-x", sender_id="attacker", timestamp=ts(-7200))
        assert only(ingest(client, forged_unsigned), "rejected")["code"] == "invalid_signature"
        assert only(ingest(client, stale_forged), "rejected")["code"] == "stale"
        body = ingest(client, genuine)
        assert only(body, "accepted")["packet_id"] == "sq"
        assert body["duplicates"] == [] and body["rejected"] == []

    def test_legacy_junk_row_does_not_block_a_genuine_packet(self, client):
        genuine = make_emergency(packet_id="legacy", emergency_id="e-l", sender_id="victim")
        db = db_session()
        junk = RawPacket(
            packet_id="legacy", sender_id="ff" * 32, type="emergency", timestamp=ts(), nonce="n",
            ttl=5, hop_count=0, protocol_version=1, signature="00", status=PacketStatus.REJECTED_SIGNATURE,
        )
        db.add(junk)
        db.commit()
        assert only(ingest(client, genuine), "accepted")
        assert db.query(RawPacket).filter(RawPacket.packet_id == "legacy").count() == 1

    def test_termination_closes_every_incident_sharing_an_emergency_id(self, client):
        # emergency_id is not sender-scoped in the frozen spec: a squatter cannot keep the genuine one open.
        a = only(ingest(client, make_emergency(packet_id="pa", emergency_id="shared", sender_id="atk", latitude=10.0, longitude=10.0)), "accepted")
        b = only(ingest(client, make_emergency(packet_id="pb", emergency_id="shared", sender_id="vic", latitude=20.0, longitude=20.0)), "accepted")
        assert a["incident_id"] != b["incident_id"]
        register_responder(client, public_key=_pubkey_hex_for("resp"))
        ingest(client, make_termination(packet_id="pt", emergency_id="shared", sender_id="resp"))
        from app.models.incident import Incident, IncidentStatus
        statuses = {i.status for i in db_session().query(Incident).all()}
        assert statuses == {IncidentStatus.CLOSED}


class TestSchemaUpgrade:
    def test_old_unique_packet_id_index_is_replaced_and_upgrade_is_idempotent(self, tmp_path):
        engine = create_engine(f"sqlite:///{tmp_path / 'old.db'}")
        with engine.begin() as conn:
            conn.execute(text("CREATE TABLE raw_packets (id INTEGER PRIMARY KEY, packet_id VARCHAR NOT NULL, sender_id VARCHAR NOT NULL)"))
            conn.execute(text("CREATE UNIQUE INDEX ix_raw_packets_packet_id ON raw_packets (packet_id)"))
        assert upgrade_raw_packet_identity(engine) is True
        indexes = {i["name"]: i for i in inspect(engine).get_indexes("raw_packets")}
        assert indexes["ix_raw_packets_packet_id"]["unique"] in (0, False)
        assert indexes["uq_raw_packets_sender_packet"]["column_names"] == ["sender_id", "packet_id"]
        assert indexes["uq_raw_packets_sender_packet"]["unique"] in (1, True)
        with engine.begin() as conn:  # same packet_id, different senders now allowed
            conn.execute(text("INSERT INTO raw_packets (packet_id, sender_id) VALUES ('p','a'), ('p','b')"))
        assert upgrade_raw_packet_identity(engine) is False


# ---------------------------------------------------------------- Phase 5

class TestTimestampContract:
    @pytest.mark.parametrize("fmt", ["z6", "z3", "z0", "ist", None])
    def test_all_timezone_forms_are_accepted(self, client, fmt):
        packet = make_emergency(packet_id=f"tf-{fmt}", emergency_id=f"e-{fmt}", timestamp=ts(-5, fmt))
        assert only(ingest(client, packet), "accepted")

    @pytest.mark.parametrize("value", [
        "2026-09-24T10:00:00",            # naive: ambiguous
        "2026-09-24",                      # date only
        "20260924T100000Z",                # basic format
        "2026-09-24 10:00:00Z",            # space separator
        "2026-13-40T10:00:00Z",            # impossible date
        "yesterday",
        " 2026-09-24T10:00:00Z",
        "2026-09-24T10:00:00z",
    ])
    def test_ambiguous_or_malformed_timestamps_rejected(self, client, value):
        entry = only(ingest(client, make_emergency(packet_id="tbad", emergency_id="e-tbad", timestamp=value)), "rejected")
        assert entry["code"] == "invalid_timestamp"

    def test_age_boundary(self, client):
        assert only(ingest(client, make_emergency(packet_id="age-ok", emergency_id="e-ok", timestamp=ts(-(contract.PACKET_MAX_AGE_SECONDS - 30)))), "accepted")
        entry = only(ingest(client, make_emergency(packet_id="age-bad", emergency_id="e-bad", timestamp=ts(-(contract.PACKET_MAX_AGE_SECONDS + 30)))), "rejected")
        assert entry["code"] == "stale"

    def test_future_skew_boundary(self, client):
        assert only(ingest(client, make_emergency(packet_id="fut-ok", emergency_id="e-fok", timestamp=ts(contract.PACKET_MAX_FUTURE_SKEW_SECONDS - 15))), "accepted")
        entry = only(ingest(client, make_emergency(packet_id="fut-bad", emergency_id="e-fbad", timestamp=ts(contract.PACKET_MAX_FUTURE_SKEW_SECONDS + 60))), "rejected")
        assert entry["code"] == "future_timestamp"

    def test_signature_covers_the_raw_timestamp_string(self, client):
        packet = make_emergency(packet_id="raw-ts", emergency_id="e-raw", timestamp=ts(-5, "z6"))
        packet["timestamp"] = packet["timestamp"].replace("Z", "+00:00")  # same instant, different bytes
        assert only(ingest(client, packet), "rejected")["code"] == "invalid_signature"

    def test_ai_age_uses_utc_regardless_of_offset(self, client, monkeypatch):
        seen = {}
        import app.services.ingest_service as svc
        real = svc.ai_analyze
        monkeypatch.setattr(svc, "ai_analyze", lambda **kw: seen.update(kw) or real(**kw))
        ingest(client, make_emergency(packet_id="ai-age", emergency_id="e-age", timestamp=ts(-120, "ist")))
        assert 100 <= seen["age_seconds"] <= 140  # IST form of "2 minutes ago" is still ~120 s, not 5.5 h off


class TestTimeParser:
    def test_dart_and_python_forms(self):
        expected = datetime(2026, 9, 24, 10, 0, 0, tzinfo=timezone.utc)
        assert parse_timestamp("2026-09-24T10:00:00Z") == expected
        assert parse_timestamp("2026-09-24T10:00:00.000Z") == expected
        assert parse_timestamp("2026-09-24T15:30:00+05:30") == expected
        assert parse_timestamp("2026-09-24T04:30:00-05:30") == expected
        assert parse_timestamp("2026-09-24T10:00:00.123456Z").microsecond == 123456
        assert parse_timestamp("2026-09-24T10:00:00.123456789Z").microsecond == 123456  # truncated, no error

    def test_result_is_always_utc_aware(self):
        assert parse_timestamp("2026-09-24T15:30:00+05:30").utcoffset() == timedelta(0)


class TestContractConstants:
    def test_documented_relationships(self):
        assert contract.PACKET_MAX_AGE_SECONDS > contract.MESH_CARRY_MAX_AGE_SECONDS  # delayed sync is legitimate
        assert contract.PACKET_TTL_MAX == 5  # MAX_TTL unchanged
        assert contract.INGEST_ACCEPTED_TYPES == ("emergency", "termination")

    def test_ai_constants_match_the_ai_service_config(self):
        from app.utils.setu_ai_import_guard import ensure_setu_ai_service_importable
        ensure_setu_ai_service_importable()
        import config as ai_config
        assert contract.AI_DEDUP_WINDOW_SECONDS == ai_config.TIME_WINDOW_SECONDS
        assert contract.AI_DEDUP_RADIUS_METERS == ai_config.GEO_DEDUP_RADIUS_METERS

    def test_dart_constants_mirrored(self):
        """Fails loudly if the Dart mesh constants this backend mirrors are edited."""
        import pathlib, re
        dart = pathlib.Path(__file__).resolve().parents[2] / "setu_app/lib/security/security_constants.dart"
        text_ = dart.read_text()
        assert re.search(r"maxPacketAge\s*=\s*Duration\(minutes:\s*5\)", text_)
        assert re.search(r"allowedClockSkew\s*=\s*Duration\(seconds:\s*30\)", text_)
        assert re.search(r"maxPacketSize\s*=\s*4096", text_)
        assert contract.MESH_CARRY_MAX_AGE_SECONDS == 300
        assert contract.PACKET_MAX_FUTURE_SKEW_SECONDS == 30
        assert contract.MAX_PACKET_BYTES == 4096
