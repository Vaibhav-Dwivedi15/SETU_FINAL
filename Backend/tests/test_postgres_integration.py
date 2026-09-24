"""
Block 3 -- PostgreSQL verification (skipped unless SETU_TEST_POSTGRES_URL is set).

Runs the Block 2 identity migration and the real ingest pipeline (including the
`pg_advisory_xact_lock` path SQLite cannot exercise and concurrent-duplicate races) against a
REAL PostgreSQL server. NEVER point this at production: it creates and drops tables in the
target database. Use a throwaway database.

    SETU_TEST_POSTGRES_URL=postgresql+psycopg2://user:pass@host:5432/scratch pytest tests/test_postgres_integration.py
"""

import os
import threading

import pytest
from sqlalchemy import create_engine, inspect, text
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import sessionmaker

URL = os.environ.get("SETU_TEST_POSTGRES_URL")
pytestmark = pytest.mark.skipif(not URL, reason="SETU_TEST_POSTGRES_URL not set (no PostgreSQL available)")

from app.db.base import Base, get_db  # noqa: E402
from app.db.init_db import upgrade_raw_packet_identity  # noqa: E402
from app.main import app  # noqa: E402
from app.models import RawPacket  # noqa: E402
from app.models.packet import PacketStatus  # noqa: E402


@pytest.fixture()
def pg():
    engine = create_engine(URL, pool_pre_ping=True)
    assert engine.dialect.name == "postgresql"
    # Safety interlock: this fixture wipes the public schema. Only ever run it on a scratch database.
    assert any(w in (engine.url.database or "") for w in ("scratch", "test")), (
        "refusing to run: the database name must contain 'scratch' or 'test' (this test DROPS EVERYTHING)"
    )

    def clean():
        with engine.begin() as conn:
            conn.execute(text("DROP SCHEMA public CASCADE"))
            conn.execute(text("CREATE SCHEMA public"))

    clean()
    Base.metadata.create_all(engine)
    yield engine
    clean()
    engine.dispose()


def make_legacy_schema(engine):
    """Recreate the PRE-Block-2 state: UNIQUE index on packet_id alone, no composite constraint."""
    with engine.begin() as conn:
        # create_all() makes the composite a CONSTRAINT on PostgreSQL (with a backing index of the same name).
        conn.execute(text("ALTER TABLE raw_packets DROP CONSTRAINT IF EXISTS uq_raw_packets_sender_packet"))
        conn.execute(text("DROP INDEX IF EXISTS uq_raw_packets_sender_packet"))
        conn.execute(text("DROP INDEX IF EXISTS ix_raw_packets_packet_id"))
        conn.execute(text("CREATE UNIQUE INDEX ix_raw_packets_packet_id ON raw_packets (packet_id)"))


def add_row(session, packet_id, sender, status=PacketStatus.VALIDATED):
    session.add(RawPacket(packet_id=packet_id, sender_id=sender, type="emergency", timestamp="2026-09-24T10:00:00Z",
                          nonce="n" * 8, ttl=5, hop_count=0, protocol_version=1, signature="00" * 64,
                          emergency_id="e-" + packet_id, status=status))
    session.commit()


def index_map(engine):
    insp = inspect(engine)
    return {i["name"]: i for i in insp.get_indexes("raw_packets")}, {c["name"]: c for c in insp.get_unique_constraints("raw_packets")}


class TestIdentityMigration:
    def test_legacy_database_is_upgraded_preserving_every_row(self, pg):
        make_legacy_schema(pg)
        Session = sessionmaker(bind=pg)
        with Session() as s:
            add_row(s, "p1", "aa" * 32)
            add_row(s, "p2", "bb" * 32)
            add_row(s, "junk", "cc" * 32, PacketStatus.REJECTED_SIGNATURE)  # legacy squatter row
        with pg.connect() as c:
            before = c.execute(text("SELECT packet_id, sender_id, status FROM raw_packets ORDER BY id")).all()
        with Session() as s, pytest.raises(IntegrityError):  # the old constraint really was single-column
            add_row(s, "p1", "dd" * 32)

        assert upgrade_raw_packet_identity(pg) is True

        with pg.connect() as c:
            after = c.execute(text("SELECT packet_id, sender_id, status FROM raw_packets ORDER BY id")).all()
        assert after == before  # nothing lost or altered
        indexes, constraints = index_map(pg)
        assert not indexes["ix_raw_packets_packet_id"]["unique"]
        assert "uq_raw_packets_sender_packet" in {**indexes, **constraints}
        with Session() as s:
            add_row(s, "p1", "dd" * 32)  # same packet_id, different sender: now legal
        with Session() as s, pytest.raises(IntegrityError):  # same (sender, packet_id): still refused
            add_row(s, "p1", "aa" * 32)

    def test_upgrade_is_idempotent_and_safe_on_a_fresh_schema(self, pg):
        assert upgrade_raw_packet_identity(pg) is False  # create_all already produced the new shape
        make_legacy_schema(pg)
        assert upgrade_raw_packet_identity(pg) is True
        assert upgrade_raw_packet_identity(pg) is False

    def test_upgrade_runs_inside_a_transaction(self, pg):
        """A failure part-way must not leave the table without ANY uniqueness guarantee."""
        make_legacy_schema(pg)
        with sessionmaker(bind=pg)() as s:
            add_row(s, "p1", "aa" * 32)
        # Pre-create a conflicting NON-unique object with the new constraint's name so CREATE UNIQUE INDEX fails.
        with pg.begin() as conn:
            conn.execute(text("CREATE TABLE uq_raw_packets_sender_packet (x int)"))
        with pytest.raises(Exception):
            upgrade_raw_packet_identity(pg)
        indexes, _ = index_map(pg)
        assert indexes["ix_raw_packets_packet_id"]["unique"], "old guarantee must survive a failed upgrade (rolled back)"

    def test_documented_rollback_works_only_without_cross_sender_reuse(self, pg):
        make_legacy_schema(pg)
        upgrade_raw_packet_identity(pg)
        rollback = ["DROP INDEX uq_raw_packets_sender_packet", "DROP INDEX ix_raw_packets_packet_id",
                    "CREATE UNIQUE INDEX ix_raw_packets_packet_id ON raw_packets (packet_id)"]
        with pg.begin() as c:
            for stmt in rollback:
                c.execute(text(stmt))
        upgrade_raw_packet_identity(pg)
        with sessionmaker(bind=pg)() as s:
            add_row(s, "same", "aa" * 32)
            add_row(s, "same", "bb" * 32)
        with pytest.raises(IntegrityError), pg.begin() as c:
            for stmt in rollback:
                c.execute(text(stmt))
        with pg.begin() as c:  # and the failed rollback left the new index in place
            assert c.execute(text("SELECT count(*) FROM pg_indexes WHERE indexname='uq_raw_packets_sender_packet'")).scalar() == 1


class TestIngestOnPostgres:
    @pytest.fixture()
    def client(self, pg):
        from fastapi.testclient import TestClient
        Session = sessionmaker(bind=pg)

        def override():
            db = Session()
            try:
                yield db
            finally:
                db.close()

        app.dependency_overrides[get_db] = override
        yield TestClient(app)
        app.dependency_overrides.clear()

    def test_pipeline_including_advisory_lock_and_dedup(self, client):
        from tests.test_ingest import make_emergency
        first = make_emergency(packet_id="pg1", emergency_id="e1", sender_id="dev-a")
        a = client.post("/ingest", json={"packets": [first]}).json()
        assert a["accepted"][0]["dedup_decision"] == "NEW_INCIDENT"
        dup = client.post("/ingest", json={"packets": [first]}).json()
        assert dup["duplicates"]
        merged = client.post("/ingest", json={"packets": [make_emergency(packet_id="pg2", emergency_id="e2", sender_id="dev-b")]}).json()
        assert merged["accepted"][0]["dedup_decision"] == "MERGED"

    def test_concurrent_identical_packets_yield_one_accept_and_no_5xx(self, client):
        from tests.test_ingest import make_emergency
        packet = make_emergency(packet_id="race1", emergency_id="e-race", sender_id="dev-r")
        results = []

        def send():
            r = client.post("/ingest", json={"packets": [packet]})
            results.append((r.status_code, r.json()))

        threads = [threading.Thread(target=send) for _ in range(8)]
        [t.start() for t in threads]
        [t.join() for t in threads]
        assert all(code == 200 for code, _ in results)
        accepted = sum(len(body["accepted"]) for _, body in results)
        others = sum(len(body["duplicates"]) + len(body["failed"]) for _, body in results)
        assert accepted == 1 and accepted + others == 8
        # a "failed" (retryable) outcome is acceptable under a race; a second ACCEPT or a 5xx is not
