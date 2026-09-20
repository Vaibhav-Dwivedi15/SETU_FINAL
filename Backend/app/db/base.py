"""
Database setup.

Creates the SQLAlchemy engine, session factory, and declarative Base class
that all ORM models will inherit from. Other modules should import
`get_db` (as a FastAPI dependency) and `Base` (for defining models) from
here — nothing else should create its own engine or session.
"""

from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker, declarative_base

from app.core.config import settings

# The engine manages the actual connection pool to PostgreSQL.
# Default pool_size=5 + max_overflow=10 (15 total) was found to bottleneck
# under load testing -- 50 concurrent /ingest requests averaged 8.5s
# latency because most were queued waiting for a free connection, not
# actually doing slow work. Bumped explicitly; pool_pre_ping avoids using
# a connection that's gone stale (e.g. after a long idle period).
engine = create_engine(
    settings.database_url,
    pool_size=20,
    max_overflow=30,
    pool_pre_ping=True,
)

# Each request gets its own Session from this factory.
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

# All ORM models (Packet, Incident, etc.) will inherit from this Base.
Base = declarative_base()


def get_db():
    """
    FastAPI dependency that yields a database session and guarantees
    it's closed afterward, even if the request raises an error.

    Usage in a route:
        @app.get("/something")
        def route(db: Session = Depends(get_db)):
            ...
    """
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()