from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from starlette.responses import JSONResponse
import logging

from app.core.config import settings
from app.routers import (
    health, ingest, register, incidents, responders, alerts,
    auth, voice, government,
)
from app.db.init_db import init_db

logging.basicConfig(level=logging.INFO)

# SEP 2026 SECURITY HARDENING: global request body-size guard.
# WHY 30MB: voice.py already enforces its own ~25MB cap on the audio
# upload specifically (see routers/voice.py) -- this is a coarser,
# earlier backstop in front of EVERY route, not a replacement for that
# check. 30MB gives voice uploads headroom above their own 25MB limit
# (so this middleware never fires before voice.py's own, more specific,
# error does) while still rejecting a request body an order of magnitude
# larger than anything this API's real endpoints need (the largest other
# body, PacketBatchIn at 500 packets, is nowhere close to this).
# Checked via Content-Length when present (cheap, no body read).
# KNOWN LIMITATION, stated plainly rather than silently: a request sent
# with chunked transfer-encoding (no Content-Length header) is NOT
# caught by this check and would need a byte-counting body read to
# guard -- not added here, since every route in this app already reads
# its body through Pydantic/FastAPI's own parsing (which has its own
# practical limits) or, for voice.py, through a more specific 25MB
# UploadFile check. This middleware is a coarse Content-Length fast
# path, not a complete guarantee against every unbounded-body shape.
MAX_REQUEST_BODY_BYTES = 30 * 1024 * 1024  # 30 MB

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


@app.middleware("http")
async def limit_request_body_size(request: Request, call_next):
    """
    Coarse, whole-API body-size guard (see MAX_REQUEST_BODY_BYTES above).

    Content-Length header, when present, is checked before touching the
    body at all -- zero extra cost for the overwhelming majority of
    requests. Does NOT guard a chunked-transfer request with no
    Content-Length (see the module-level comment above this function's
    definition). Fail-open on any error here (matches
    core/rate_limit.py's own fail-open stance): a bug in this guard must
    never become a way to deny service to a legitimate request,
    especially not /ingest during an actual disaster.
    """
    try:
        content_length = request.headers.get("content-length")
        if content_length is not None and int(content_length) > MAX_REQUEST_BODY_BYTES:
            return JSONResponse(
                status_code=413,
                content={"detail": "Request body too large."},
            )
    except (TypeError, ValueError):
        # Malformed Content-Length -- let the request proceed; FastAPI's
        # own body parsing will reject it on its own terms.
        pass
    except Exception:
        pass

    return await call_next(request)


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


@app.get("/")
async def root():
    return {
        "message": "SETU Backend is running!",
        "status": "healthy",
        "version": "1.0.0"
    }
