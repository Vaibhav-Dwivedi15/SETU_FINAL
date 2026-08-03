"""
One-off script: drops incidents / raw_packets / incident_audit_log
(and their FK constraints) so init_db.py can recreate them fresh with
the current model schema -- specifically, Incident's new
sender_priority + ai_* columns from the AI integration.

Run once from the Backend/ folder, inside your venv:
    python drop_and_recreate_incident_tables.py

Reuses the app's own DATABASE_URL (via app.core.config.settings /
app.db.base.engine) -- the same one your app already connects to Neon
with -- so there's no psql, no shell variable expansion, and no need to
copy the connection string anywhere.

WARNING: this permanently deletes all existing incidents, raw packets,
and audit log rows. user_profiles / responder_profiles are untouched --
this only drops the three tables listed below.
"""

from sqlalchemy import text

from app.db.base import engine
from app.db.init_db import init_db

TABLES_TO_DROP = ["incident_audit_log", "raw_packets", "incidents"]


def main():
    with engine.begin() as conn:
        for table in TABLES_TO_DROP:
            conn.execute(text(f"DROP TABLE IF EXISTS {table} CASCADE"))
            print(f"Dropped {table} (if it existed)")

    init_db()
    print("Done -- tables recreated with current schema.")


if __name__ == "__main__":
    main()
