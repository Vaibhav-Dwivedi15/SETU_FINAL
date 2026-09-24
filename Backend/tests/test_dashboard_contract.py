"""
Block 2 -- dashboard contract. The backend's IncidentOut must carry every field
the dashboard reads (tests/contract/incident_out.example.json is the shared
golden example: this test proves the LIVE response matches it, and
setu_dashboard/tests/contract.test.mjs proves the dashboard consumes it).

Regenerate the example deliberately with UPDATE_CONTRACT_FIXTURES=1.
"""

import json
import os
import pathlib

import pytest

from app.services.incident_service import display_priority
from tests.test_ingest import _pubkey_hex_for, client, make_emergency, make_termination, register_responder  # noqa: F401
from tests.test_ingest_contract import db_session, ingest, only

FIXTURE = pathlib.Path(__file__).parent / "contract" / "incident_out.example.json"
API_KEY = "test-responder-api-key"


@pytest.fixture()
def authed(client):
    from app.core.config import settings
    original = settings.responder_api_key
    settings.responder_api_key = API_KEY
    yield client, {"x-api-key": API_KEY}
    settings.responder_api_key = original


def type_name(value):
    return "null" if value is None else type(value).__name__


class TestIncidentOutContract:
    def test_live_response_matches_shared_example(self, authed):
        client, headers = authed
        packet = make_emergency(packet_id="dc1", emergency_id="e-dc1", incident_type="fire")
        packet["hop_count"] = 2
        # relay_path is not signed; a relayed packet may carry it
        packet["relay_path"] = ["h1a2b3c4d", "h5e6f7a8b"]
        ingest(client, packet)
        rows = client.get("/incidents", headers=headers).json()
        assert len(rows) == 1
        live = rows[0]

        if os.environ.get("UPDATE_CONTRACT_FIXTURES"):
            FIXTURE.write_text(json.dumps(live, indent=2, sort_keys=True) + "\n")
        example = json.loads(FIXTURE.read_text())

        assert set(live) == set(example), f"IncidentOut fields drifted: {set(live) ^ set(example)}"
        for key, value in example.items():
            if value is not None and live[key] is not None:
                assert type_name(live[key]) == type_name(value), key

    def test_carries_every_field_the_dashboard_reads(self, authed):
        client, headers = authed
        ingest(client, make_emergency(packet_id="dc2", emergency_id="e-dc2"))
        live = client.get("/incidents", headers=headers).json()[0]
        required = {
            "id", "incident_type", "latitude", "longitude", "status", "hop_count", "relay_path",
            "sender_priority", "ai_incident_type", "ai_incident_confidence", "ai_incident_explanation",
            "ai_urgency", "ai_urgency_confidence", "ai_urgency_explanation", "ai_priority",
            "display_priority", "report_count", "created_at", "updated_at", "closed_at",
        }
        assert required <= set(live)

    def test_values_are_authoritative(self, authed):
        client, headers = authed
        packet = make_emergency(packet_id="dc3", emergency_id="e-dc3", incident_type="fire")
        packet["hop_count"] = 3
        packet["relay_path"] = ["aa", "bb", "cc"]
        ingest(client, packet)
        live = client.get("/incidents", headers=headers).json()[0]
        assert live["status"] == "OPEN" and live["closed_at"] is None
        assert live["sender_priority"] == "high"
        assert live["hop_count"] == 3 and live["relay_path"] == ["aa", "bb", "cc"]
        assert live["ai_priority"] is not None and 1.0 <= live["ai_priority"] <= 5.0
        assert live["ai_urgency"] is not None
        assert live["display_priority"] == display_priority(live["ai_priority"], live["sender_priority"])
        assert (live["latitude"], live["longitude"]) == (28.6139, 77.209)
        assert live["report_count"] == 1

    def test_report_count_reflects_merged_reports(self, authed):
        client, headers = authed
        ingest(client, make_emergency(packet_id="rc1", emergency_id="e-rc1", sender_id="dev-a"))
        ingest(client, make_emergency(packet_id="rc2", emergency_id="e-rc2", sender_id="dev-b"))
        rows = client.get("/incidents", headers=headers).json()
        assert len(rows) == 1 and rows[0]["report_count"] == 2

    def test_closed_incident_status_and_closed_at(self, authed):
        client, headers = authed
        register_responder(client, public_key=_pubkey_hex_for("resp-1"))
        ingest(client, make_emergency(packet_id="cl1", emergency_id="e-cl1"))
        ingest(client, make_termination(packet_id="cl-t", emergency_id="e-cl1", sender_id="resp-1"))
        live = client.get("/incidents", headers=headers).json()[0]
        assert live["status"] == "CLOSED" and live["closed_at"] is not None

    def test_resolve_endpoint_returns_the_same_shape(self, authed):
        client, headers = authed
        ingest(client, make_emergency(packet_id="rs1", emergency_id="e-rs1"))
        listed = client.get("/incidents", headers=headers).json()[0]
        resolved = client.post(f"/incidents/{listed['id']}/resolve", headers=headers).json()
        assert set(resolved) == set(listed) and resolved["status"] == "CLOSED"

    def test_history_entries_carry_id_and_dedup_evidence(self, authed):
        client, headers = authed
        ingest(client, make_emergency(packet_id="h1", emergency_id="e-h1", sender_id="dev-a"))
        ingest(client, make_emergency(packet_id="h2", emergency_id="e-h2", sender_id="dev-b"))
        history = client.get("/incidents/1/history", headers=headers).json()
        assert [h["action"] for h in history] == ["CREATED", "MERGED"]
        assert all("id" in h for h in history)
        assert "dedup=" in history[1]["detail"]

    @pytest.mark.parametrize("ai,sender,label", [
        (4.5, None, "Critical"), (4.49, None, "High"), (3.5, "low", "High"), (3.49, None, "Medium"),
        (2.0, None, "Medium"), (1.99, "critical", "Low"), (None, "critical", "Critical"),
        (None, "HIGH", "High"), (None, None, "Medium"), (None, "bogus", "Medium"),
    ])
    def test_display_priority_rule(self, ai, sender, label):
        assert display_priority(ai, sender) == label

    def test_incident_list_requires_api_key(self, client):
        assert client.get("/incidents").status_code == 401
