"""
Creates all tables from the current models, then applies the small, idempotent
schema upgrades that create_all() cannot (it never alters existing tables).

Run manually with: python -m app.db.init_db  (also runs at app startup).
Stand-in for Alembic migrations while the schema is still moving.
"""

import logging

from sqlalchemy import inspect, text

from app.db.base import Base, engine
from app.models import RawPacket, Incident, UserProfile, ResponderProfile  # noqa: F401  (import registers tables)

logger = logging.getLogger("setu.init_db")


def upgrade_raw_packet_identity(bind=None) -> bool:
    """
    Block 2 (packet-ID squatting): raw_packets.packet_id used to be UNIQUE on
    its own. It is now unique per (sender_id, packet_id) -- see models/packet.py.
    On an existing database, drop the old single-column unique index and let
    the new composite unique constraint be created. Safe to run repeatedly.
    Returns True if it changed anything.
    """
    bind = bind or engine
    insp = inspect(bind)
    if "raw_packets" not in insp.get_table_names():
        return False

    changed = False
    with bind.begin() as conn:
        for index in insp.get_indexes("raw_packets"):
            if index.get("unique") and index.get("column_names") == ["packet_id"]:
                conn.execute(text(f'DROP INDEX "{index["name"]}"'))
                conn.execute(text('CREATE INDEX IF NOT EXISTS ix_raw_packets_packet_id ON raw_packets (packet_id)'))
                changed = True
        # A UNIQUE *constraint* (rather than index) on packet_id (Postgres names it
        # raw_packets_packet_id_key) must be dropped as a constraint.
        for constraint in insp.get_unique_constraints("raw_packets"):
            if constraint.get("column_names") == ["packet_id"] and constraint.get("name"):
                conn.execute(text(f'ALTER TABLE raw_packets DROP CONSTRAINT "{constraint["name"]}"'))
                changed = True
        existing_names = {i["name"] for i in inspect(conn).get_indexes("raw_packets")}
        existing_names |= {c["name"] for c in inspect(conn).get_unique_constraints("raw_packets")}
        if "uq_raw_packets_sender_packet" not in existing_names:
            conn.execute(text(
                "CREATE UNIQUE INDEX uq_raw_packets_sender_packet ON raw_packets (sender_id, packet_id)"
            ))
            changed = True
    if changed:
        logger.info("raw_packets identity upgraded to UNIQUE(sender_id, packet_id)")
    return changed


def init_db() -> None:
    Base.metadata.create_all(bind=engine)
    upgrade_raw_packet_identity()
    print("Tables created/verified.")


if __name__ == "__main__":
    init_db()
