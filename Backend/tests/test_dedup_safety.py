"""
Block 2 -- explainable, backend-verified incident dedup.

The AI service PROPOSES a merge; the backend decides. Every accepted emergency
returns dedup_decision / matched_incident_id / dedup_reason / dedup_evidence.
"""

import pytest

from app.models.incident import Incident, IncidentStatus
from tests.test_ingest import _pubkey_hex_for, _sign_packet, client, make_emergency, make_termination, register_responder  # noqa: F401
from tests.test_ingest_contract import db_session, ingest, only

DELHI = (28.6139, 77.2090)


def emergency(pid, message, lat=DELHI[0], lon=DELHI[1], sender="dev-1", incident_type=None, priority="high"):
    packet = make_emergency(packet_id=pid, emergency_id=f"e-{pid}", sender_id=sender, latitude=lat, longitude=lon)
    packet["message"] = message
    packet["priority"] = priority
    if incident_type is None:
        packet.pop("incident_type", None)
    else:
        packet["incident_type"] = incident_type
    packet["signature"] = _sign_packet(packet, sender)
    return packet


def submit(client, *args, **kwargs):
    return only(ingest(client, emergency(*args, **kwargs)), "accepted")


class TestDedupScenarios:
    def test_same_incident_merges_with_evidence(self, client):
        first = submit(client, "a1", "Fire in Block A, people trapped", sender="dev-a")
        second = submit(client, "a2", "Fire in Block A, people trapped", sender="dev-b")
        assert first["dedup_decision"] == "NEW_INCIDENT" and first["dedup_reason"] == "no_ai_match"
        assert second["dedup_decision"] == "MERGED"
        assert second["dedup_reason"] == "ai_match_accepted"
        assert second["matched_incident_id"] == first["incident_id"] == second["incident_id"]
        ev = second["dedup_evidence"]
        assert ev["similarity"] >= 0.75 and ev["match_method"] in ("lexical", "embedding")
        assert ev["distance_meters"] is not None and ev["backend_distance_meters"] < 500

    def test_nearby_duplicate_within_radius_merges(self, client):
        submit(client, "n1", "Fire in Block A, people trapped", sender="dev-a")
        near = submit(client, "n2", "Fire in Block A, people trapped!", lat=DELHI[0] + 0.002, lon=DELHI[1], sender="dev-b")  # ~220 m
        assert near["dedup_decision"] == "MERGED"

    def test_different_incident_nearby_stays_separate(self, client):
        a = submit(client, "d1", "Fire in Block A, people trapped", sender="dev-a")
        b = submit(client, "d2", "Bridge collapsed, vehicles fell into river", sender="dev-b")
        assert b["dedup_decision"] == "NEW_INCIDENT" and b["incident_id"] != a["incident_id"]

    def test_same_text_different_location_stays_separate(self, client):
        a = submit(client, "l1", "Fire in Block A, people trapped", sender="dev-a")
        b = submit(client, "l2", "Fire in Block A, people trapped", lat=19.0760, lon=72.8777, sender="dev-b")
        assert b["dedup_decision"] == "NEW_INCIDENT" and b["incident_id"] != a["incident_id"]

    def test_same_location_different_disaster_is_not_merged(self, client):
        a = submit(client, "c1", "Fire in Block A", sender="dev-a")
        b = submit(client, "c2", "Flood in Block A", sender="dev-b")
        assert b["incident_id"] != a["incident_id"]
        assert b["dedup_decision"] == "NEW_INCIDENT"

    def test_different_category_proposed_by_ai_is_vetoed(self, client, monkeypatch):
        """Force the AI to (wrongly) propose merging a medical report into a fire incident."""
        import app.services.ingest_service as svc
        real = svc.ai_analyze
        first = submit(client, "k1", "Fire in Block A", sender="dev-a")

        def forced(**kw):
            result = real(**kw) or {}
            result.update(is_duplicate=True, matched_cluster_id="e-k1", ai_incident_type="Medical")
            return result

        monkeypatch.setattr(svc, "ai_analyze", forced)
        second = submit(client, "k2", "Man collapsed, bleeding badly", sender="dev-b")
        assert second["dedup_decision"] == "NEW_INCIDENT"
        assert second["dedup_reason"] == "ai_match_vetoed_category"
        assert second["incident_id"] != first["incident_id"]
        assert second["dedup_evidence"]["vetoed_incident_id"] == first["incident_id"]

    def test_ai_match_beyond_radius_is_vetoed_by_backend_distance(self, client, monkeypatch):
        import app.services.ingest_service as svc
        real = svc.ai_analyze
        first = submit(client, "g1", "Fire in Block A", sender="dev-a")

        def forced(**kw):
            result = real(**kw) or {}
            result.update(is_duplicate=True, matched_cluster_id="e-g1", distance_meters=10.0)  # AI claims 10 m
            return result

        monkeypatch.setattr(svc, "ai_analyze", forced)
        far = submit(client, "g2", "Fire in Block A", lat=DELHI[0] + 0.05, lon=DELHI[1], sender="dev-b")  # ~5.5 km
        assert far["dedup_reason"] == "ai_match_vetoed_distance" and far["incident_id"] != first["incident_id"]

    def test_ai_cluster_with_no_incident_is_vetoed(self, client, monkeypatch):
        import app.services.ingest_service as svc
        real = svc.ai_analyze
        monkeypatch.setattr(svc, "ai_analyze", lambda **kw: {**(real(**kw) or {}), "is_duplicate": True, "matched_cluster_id": "ghost"})
        entry = submit(client, "u1", "Fire in Block A")
        assert entry["dedup_decision"] == "NEW_INCIDENT" and entry["dedup_reason"] == "ai_match_vetoed_unresolved"

    def test_closed_incident_cannot_silently_absorb_a_new_emergency(self, client):
        register_responder(client, public_key=_pubkey_hex_for("resp-1"))
        old = submit(client, "z1", "Fire in Block A, people trapped", sender="dev-a")
        ingest(client, make_termination(packet_id="z-t", emergency_id="e-z1", sender_id="resp-1"))
        assert db_session().query(Incident).one().status == IncidentStatus.CLOSED

        # A NEW emergency at the same place, same words, inside the AI's 300 s window.
        new = submit(client, "z2", "Fire in Block A, people trapped", sender="dev-b")
        assert new["dedup_decision"] == "NEW_INCIDENT"
        assert new["dedup_reason"] == "ai_match_vetoed_closed"
        assert new["incident_id"] != old["incident_id"]
        statuses = {i.id: i.status for i in db_session().query(Incident).all()}
        assert statuses[old["incident_id"]] == IncidentStatus.CLOSED  # untouched
        assert statuses[new["incident_id"]] == IncidentStatus.OPEN

        # ...and a third report joins the NEW open incident (backend fallback), not the closed one.
        third = submit(client, "z3", "Fire in Block A, people trapped", sender="dev-c")
        assert third["incident_id"] == new["incident_id"]
        assert third["dedup_decision"] == "MERGED" and third["dedup_reason"] == "fallback_match"
        assert third["dedup_evidence"]["ai_veto"] == "ai_match_vetoed_closed"

    def test_report_without_gps_merges_on_text_but_is_flagged_unverified(self, client):
        first = submit(client, "w1", "Fire in Block A, people trapped", sender="dev-a")
        packet = emergency("w2", "Fire in Block A, people trapped", sender="dev-b")
        packet["latitude"] = packet["longitude"] = None
        packet["signature"] = _sign_packet(packet, "dev-b")
        second = only(ingest(client, packet), "accepted")
        assert second["dedup_decision"] == "MERGED" and second["incident_id"] == first["incident_id"]
        assert second["dedup_evidence"]["location_verified"] is False

    def test_ai_unavailable_uses_backend_fallback_and_says_so(self, client, monkeypatch):
        import app.services.ingest_service as svc
        monkeypatch.setattr(svc, "ai_analyze", lambda **kw: None)
        a = submit(client, "f1", "Fire in Block A", sender="dev-a", incident_type="fire")
        b = submit(client, "f2", "Fire in Block A", sender="dev-b", incident_type="fire")
        assert a["dedup_reason"] == "fallback_no_match"
        assert b["dedup_decision"] == "MERGED" and b["dedup_reason"] == "fallback_match" and b["incident_id"] == a["incident_id"]

    def test_audit_trail_records_the_reason(self, client):
        submit(client, "t1", "Fire in Block A, people trapped", sender="dev-a")
        submit(client, "t2", "Fire in Block A, people trapped", sender="dev-b")
        from app.models.audit_log import IncidentAuditLog
        details = [r.detail for r in db_session().query(IncidentAuditLog).order_by(IncidentAuditLog.id)]
        assert details[0].startswith("dedup=no_ai_match")
        assert "dedup=ai_match_accepted" in details[1] and "matched_incident=1" in details[1]


class TestAiServiceDedupReason:
    def test_check_duplicate_explains_itself(self):
        from app.utils.setu_ai_import_guard import ensure_setu_ai_service_importable
        ensure_setu_ai_service_importable()
        from models.duplicate_detector import check_duplicate, reset_clusters
        reset_clusters()
        assert check_duplicate("Fire in Block A", "x1", 28.6, 77.2)["dedup_reason"] == "no_similar_recent_report"
        assert check_duplicate("Fire in Block A", "x2", 28.6001, 77.2)["dedup_reason"] == "text_and_geo_match"
        reset_clusters()
        check_duplicate("Fire in Block A", "y1", 28.6, 77.2)
        assert check_duplicate("Fire in Block A", "y2", 0.0, 0.0)["dedup_reason"] == "text_match_location_unverified"
