from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse
from fastapi.middleware.cors import CORSMiddleware
import logging

from app.core.body_limit import BodySizeLimitMiddleware
from app.core.config import settings
from app.core.security_headers import SecurityHeadersMiddleware
from app.core.startup_checks import production_config_findings
from app.routers import (
    health, ingest, register, incidents, responders, alerts,
    auth, voice, government, responder_auth,
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
    for finding in production_config_findings():
        logging.getLogger("setu.config").warning("CONFIG: %s", finding)
    yield


# Block 3: interactive docs / schema are development tools; in production they only
# advertise the attack surface, so they are off unless DEBUG=true.
app = FastAPI(
    title="SETU Backend API",
    description="Backend for the SETU Disaster Communication Platform",
    version="1.0.0",
    lifespan=lifespan,
    docs_url="/docs" if settings.debug else None,
    redoc_url="/redoc" if settings.debug else None,
    openapi_url="/openapi.json" if settings.debug else None,
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
    # Block 3: no cookies are used (bearer tokens), so credentials stay off; methods and
    # headers are the explicit set the dashboard needs. Never "*".
    allow_credentials=False,
    allow_methods=["GET", "POST", "OPTIONS"],
    allow_headers=["Authorization", "Content-Type"],
    max_age=600,
)


# Block 2: byte-counting body cap (independent of Content-Length; per-path
# limits) -- see app/core/body_limit.py. Replaces the Content-Length-only guard.
app.add_middleware(BodySizeLimitMiddleware)
app.add_middleware(SecurityHeadersMiddleware)  # outermost of the two: also stamps 413/CORS responses


@app.exception_handler(Exception)
async def unhandled_exception_handler(request: Request, exc: Exception):
    """
    Last-resort handler (Block 2): an unexpected error becomes a generic JSON 500.
    The client never receives a traceback, exception text, SQL or a file path;
    the details go to the server log only.
    """
    logging.getLogger("setu.errors").exception("Unhandled error on %s %s", request.method, request.url.path)
    return JSONResponse(status_code=500, content={"detail": "Internal server error."})


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
# Government notification adapter log (mock adapter -- see routers/government.py).
app.include_router(government.router)
# Block 3: dashboard session login (responder key -> short-lived bearer token).
app.include_router(responder_auth.router)


@app.get("/")
async def root():
    return {
        "message": "SETU Backend is running!",
        "status": "healthy",
        "version": "1.0.0"
    }
