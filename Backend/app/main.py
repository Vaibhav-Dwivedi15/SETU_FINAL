from contextlib import asynccontextmanager

from fastapi import FastAPI
import logging

from app.routers import health, ingest, register, incidents, responders
from app.db.init_db import init_db

logging.basicConfig(level=logging.INFO)


@asynccontextmanager
async def lifespan(app: FastAPI):
    """
    Creates any missing tables on boot. Stand-in for Alembic migrations
    (see app/db/init_db.py) -- fine while the schema is still moving,
    but should be replaced with real migrations before anything
    resembling a production launch, since create_all() only ever adds
    missing tables, it never alters existing ones (that's exactly the
    manual drop-and-recreate dance we've been doing locally).
    """
    init_db()
    yield


app = FastAPI(
    title="SETU Backend API",
    description="Backend for the SETU Disaster Communication Platform",
    version="1.0.0",
    lifespan=lifespan,
)

app.include_router(health.router)
app.include_router(ingest.router)
app.include_router(register.router)
app.include_router(incidents.router)
app.include_router(responders.router)


@app.get("/")
async def root():
    return {
        "message": "SETU Backend is running!",
        "status": "healthy",
        "version": "1.0.0"
    }