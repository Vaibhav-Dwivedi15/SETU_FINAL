from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
import logging

from app.core.config import settings
from app.routers import health, ingest, register, incidents, responders, alerts
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

# Aug 6 2026: real CORS middleware, actually wired for the first time.
# WHY THIS WAS MISSING: an env var CORS_ALLOWED_ORIGINS_RAW was set on
# Render at some point, but no code anywhere in this app ever read it --
# Settings' old model had no field with that name, and extra="ignore"
# meant it was silently dropped every boot. Whatever cross-origin
# behavior was previously observed working was NOT this env var doing
# anything. settings.cors_allowed_origins (see core/config.py) now
# actually parses it, with a safe default covering the known production
# dashboard + local dev ports so this never silently breaks again.
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_allowed_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(health.router)
app.include_router(ingest.router)
app.include_router(register.router)
app.include_router(incidents.router)
app.include_router(responders.router)
app.include_router(alerts.router)


@app.get("/")
async def root():
    return {
        "message": "SETU Backend is running!",
        "status": "healthy",
        "version": "1.0.0"
    }
