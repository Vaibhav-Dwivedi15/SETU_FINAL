from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
import logging

from app.core.config import settings
from app.routers import (
    health, ingest, register, incidents, responders, alerts,
    auth, voice, government,
)
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
MAX_REQUEST_BODY_BYTES = 10_000_000
from starlette.requests import Request
from starlette.responses import JSONResponse

@app.middleware("http")
async def limit_upload_size(request: Request, call_next):
    if request.headers.get("content-length"):
        length = int(request.headers["content-length"])
        if length > MAX_REQUEST_BODY_BYTES:
            return JSONResponse({"detail": "Payload too large"}, status_code=413)
    response = await call_next(request)
    return response

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
# Email OTP auth (replaces the mobile app's demo client-side OTP).
app.include_router(auth.router)
# Voice SOS ingest -- spoken distress reports, transcribed via Whisper.
app.include_router(voice.router)
app.include_router(government.router)

# GIS and Data Infrastructure (SIH26191)
from app.routers import risk, vulnerability, relocation, datasets, history, red_zones, scenarios, ai_analytics, field_ops
app.include_router(datasets.router)
app.include_router(history.router)
app.include_router(red_zones.router)
app.include_router(risk.router)
app.include_router(vulnerability.router)
app.include_router(relocation.router)
app.include_router(scenarios.router)
app.include_router(ai_analytics.router)
app.include_router(field_ops.router)


@app.get("/")
async def root():
    return {
        "message": "SETU Backend is running!",
        "status": "healthy",
        "version": "1.0.0"
    }
