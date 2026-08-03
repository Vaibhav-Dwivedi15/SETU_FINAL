"""
One-off script to create all tables in the database from the current models.

Run manually with: python -m app.db.init_db

This is a stand-in for Alembic migrations during early development.
Once the schema stabilizes, we'll switch to Alembic so schema changes
are tracked and reversible instead of just re-run each time.
"""

from app.db.base import Base, engine
from app.models import RawPacket, Incident, UserProfile, ResponderProfile  # noqa: F401  (import registers tables)


def init_db() -> None:
    Base.metadata.create_all(bind=engine)
    print("Tables created: raw_packets, incidents, user_profiles, responder_profiles")


if __name__ == "__main__":
    init_db()