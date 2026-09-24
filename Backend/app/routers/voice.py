"""
Voice SOS ingest -- POST /ingest/voice

Lets a distress report be filed by SPEAKING instead of typing. This
matters for SETU's actual use case more than it might look: in a real
emergency, someone injured, panicking, in the dark, or not literate in a
typed script often cannot type a coherent message, but can speak one.

MULTILINGUAL -- WHAT'S REAL AND WHAT ISN'T:
Whisper's translate task means a user can speak Hindi, Bengali, Tamil,
Marathi, or any other language Whisper supports, and the pipeline
understands it. That's genuinely multilingual input, and it's the
strongest multilingual claim this project can honestly make.
What it does NOT do: preserve the original-language wording. The stored
message is the ENGLISH translation. See
app/services/voice_transcription_service.py for the AI team's own
reasoning on that tradeoff. Do not describe this as "the message is kept
in the user's language" -- it isn't.

WHY THIS IS A SEPARATE ROUTE FROM /ingest:
/ingest takes a batch of cryptographically signed mesh packets. A voice
file is not a mesh packet -- it can't be, because audio is far too large
to relay over BLE/Wi-Fi Direct hop-by-hop, which is the whole constraint
SETU is designed around. So this route is for a device that HAS
connectivity and wants to file a spoken report directly.

SIGNATURE / TRUST -- READ THIS BEFORE DEMOING:
Packets arriving via /ingest are Ed25519-signed mesh packets. A voice upload
is not a mesh packet (no packet signature over audio exists in the frozen
spec), but since Block 2 the REQUEST is signed with the same device key
(services/request_auth.py), so the caller must hold the private key for the
sender_id it claims, cannot replay a captured request, and cannot attach
voice to another sender's emergency. It still carries less than the mesh
path's guarantees: the transcript is unsigned machine output, and any fresh
keypair can file a report (there is no identity issuance in SETU).
"""
import logging
import math
import os
import tempfile
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

from fastapi import APIRouter, Depends, File, Form, HTTPException, Request, UploadFile
from sqlalchemy.orm import Session

from app.db.base import get_db
from app.models.audit_log import IncidentAuditLog, AuditAction
from app.models.packet import RawPacket, PacketStatus
from app.schemas.packet import PacketIn, PacketType, PriorityLevel
from app.services.ai_analysis_service import analyze as ai_analyze
from app.core.rate_limit import voice_ip_limiter, voice_sender_limiter
from app.services.incident_service import process_sos_packet
from app.services.request_auth import SignedHeaders, body_hash, signed_headers, verify_signed_request
from app.services.voice_transcription_service import transcribe, transcription_available

logger = logging.getLogger("setu.voice_ingest")

router = APIRouter()

# Whisper handles common audio containers; this cap exists so a stray
# large upload can't exhaust the instance's disk or memory. 25MB is far
# more than any realistic distress recording.
MAX_AUDIO_BYTES = 25 * 1024 * 1024

ALLOWED_SUFFIXES = {".wav", ".mp3", ".m4a", ".ogg", ".oga", ".webm", ".flac", ".aac", ".mp4"}


def _sniff_audio(data: bytes) -> bool:
    """
    Cheap magic-byte check so arbitrary uploads are not handed to ffmpeg.
    Covers the containers in ALLOWED_SUFFIXES: WAV/RIFF, MP3 (ID3 / frame sync),
    AAC (ADTS), Ogg, FLAC, MP4/M4A (ftyp), WebM/Matroska (EBML).
    """
    head = data[:16]
    return (
        (head[:4] == b"RIFF" and head[8:12] == b"WAVE")
        or head[:3] == b"ID3"
        or (len(head) > 1 and head[0] == 0xFF and (head[1] & 0xE0) == 0xE0)  # MP3 / ADTS frame sync
        or head[:4] == b"OggS"
        or head[:4] == b"fLaC"
        or head[4:8] == b"ftyp"
        or head[:4] == b"\x1aE\xdf\xa3"
    )


ALLOWED_CONTENT_TYPE_PREFIXES = ("audio/", "video/mp4", "video/webm", "application/octet-stream", "application/ogg")
MAX_FILENAME_CHARS = 255
MAX_EMERGENCY_ID_CHARS = 256
_VOICE_PRIORITIES = {"low", "medium", "high", "critical"}


def _parse_coordinate(raw: str, name: str, limit: float) -> float:
    try:
        value = float(raw)
    except (TypeError, ValueError):
        raise HTTPException(status_code=422, detail=f"{name} must be a number.")
    if not math.isfinite(value) or not (-limit <= value <= limit):
        raise HTTPException(status_code=422, detail=f"{name} must be between -{limit:g} and {limit:g}.")
    return value


@router.post("/ingest/voice")
async def ingest_voice_sos(
    request: Request,
    file: UploadFile = File(..., description="Audio recording of the distress message"),
    sender_id: Optional[str] = Form(None, description="Optional; if present must equal the authenticated key (X-Setu-Sender)"),
    latitude: str = Form("0.0"),
    longitude: str = Form("0.0"),
    priority: Optional[str] = Form(None, description="low | medium | high | critical"),
    emergency_id: Optional[str] = Form(None, description="Optional: attach to one of the caller's OWN existing emergencies"),
    db: Session = Depends(get_db),
    headers: SignedHeaders = Depends(signed_headers),
):
    """
    Transcribes an uploaded audio file and runs the resulting text through the
    same emergency pipeline a typed SOS uses (AI triage, dedup, incident
    create/merge, idempotent contact SMS, government adapter).

    AUTHENTICATION (Block 2): the request must be signed with the caller's
    Ed25519 device key (see services/request_auth.py; parts = [sha256(audio),
    latitude, longitude, priority, emergency_id] as the raw form strings). The
    authenticated key IS the sender identity -- a form field can no longer
    impersonate anyone -- and `emergency_id`, if supplied, must belong to that
    same key. Failures are controlled 4xx, never 500.
    """
    voice_ip_limiter.check(request)

    if not transcription_available():
        raise HTTPException(
            status_code=503,
            detail=(
                "Voice transcription is not available on this server. It requires the "
                "openai-whisper package and a system ffmpeg install; neither is present "
                "by default on a fresh deployment."
            ),
        )

    filename = file.filename or ""
    if len(filename) > MAX_FILENAME_CHARS:
        raise HTTPException(status_code=422, detail="Filename too long.")
    suffix = Path(filename).suffix.lower() or ".wav"
    if suffix not in ALLOWED_SUFFIXES:
        raise HTTPException(
            status_code=415,
            detail=f"Unsupported audio format '{suffix}'. Supported: {', '.join(sorted(ALLOWED_SUFFIXES))}",
        )
    content_type = (file.content_type or "application/octet-stream").lower()
    if not content_type.startswith(ALLOWED_CONTENT_TYPE_PREFIXES):
        raise HTTPException(status_code=415, detail=f"Unsupported content type '{content_type[:64]}'.")

    contents = await file.read(MAX_AUDIO_BYTES + 1)  # bounded read: never buffer more than the cap
    if len(contents) == 0:
        raise HTTPException(status_code=400, detail="Uploaded audio file is empty.")
    if len(contents) > MAX_AUDIO_BYTES:
        raise HTTPException(
            status_code=413,
            detail=f"Audio file too large. Limit is {MAX_AUDIO_BYTES} bytes.",
        )
    if not _sniff_audio(contents):
        raise HTTPException(status_code=415, detail="File content does not look like a supported audio recording.")

    # --- authenticate: possession of the sender's Ed25519 key -----------------
    if emergency_id is not None and len(emergency_id) > MAX_EMERGENCY_ID_CHARS:
        raise HTTPException(status_code=422, detail="emergency_id too long.")
    signer = verify_signed_request(
        db, headers, "POST", request.url.path,
        [body_hash(contents), latitude, longitude, priority or "", emergency_id or ""],
    )
    voice_sender_limiter.check(request, key=signer)
    if sender_id is not None and sender_id != signer:
        raise HTTPException(status_code=403, detail="sender_id does not match the authenticated key.")

    lat = _parse_coordinate(latitude, "latitude", 90.0)
    lon = _parse_coordinate(longitude, "longitude", 180.0)
    priority_level = None
    if priority:
        if priority.lower() not in _VOICE_PRIORITIES:
            raise HTTPException(status_code=422, detail="priority must be one of: low, medium, high, critical.")
        priority_level = PriorityLevel(priority.lower())

    if emergency_id:
        owned = (
            db.query(RawPacket.id)
            .filter(RawPacket.emergency_id == emergency_id, RawPacket.sender_id == signer)
            .first()
        )
        if not owned:
            raise HTTPException(
                status_code=403,
                detail="emergency_id is not associated with the authenticated sender.",
            )

    with tempfile.NamedTemporaryFile(delete=False, suffix=suffix) as tmp:
        tmp.write(contents)
        tmp_path = tmp.name

    try:
        transcript = transcribe(tmp_path)
    finally:
        # Always remove the temp file, even if transcription raised.
        # Audio of someone's emergency must not linger on disk.
        try:
            os.unlink(tmp_path)
        except OSError:
            logger.warning("Could not delete temp audio file")

    if not transcript:
        raise HTTPException(
            status_code=422,
            detail=(
                "Could not transcribe the audio. It may be silent, corrupted, or in an "
                "unsupported encoding. Try recording again, or send a typed message instead."
            ),
        )
    transcript = transcript.strip()[:2000]  # PacketIn.message bound; never let a long transcript 500

    resolved_emergency_id = emergency_id or f"voice-{uuid.uuid4().hex[:12]}"
    now = datetime.now(timezone.utc)

    # Build a PacketIn so the rest of the pipeline sees exactly the shape it
    # already handles. hop_count=0 is truthful (arrived directly over the
    # internet). The `signature` column records that this row was authorised by a
    # signed REQUEST (not a mesh packet signature) -- see request_auth.py.
    packet = PacketIn(
        packet_id=f"voice-{uuid.uuid4().hex}",
        sender_id=signer,
        type=PacketType.EMERGENCY,
        timestamp=now.isoformat(),
        nonce=uuid.uuid4().hex,
        ttl=0,
        hop_count=0,
        protocol_version=1,
        signature=f"signed-voice-request:{headers.signature}",
        emergency_id=resolved_emergency_id,
        latitude=lat,
        longitude=lon,
        message=transcript,
        priority=priority_level,
    )

    raw = RawPacket(
        **packet.model_dump(exclude={"incident_type", "type", "priority"}),
        incident_type=None,
        type=packet.type.value,
        priority=packet.priority.value if packet.priority else None,
        status=PacketStatus.VALIDATED,
    )
    db.add(raw)
    db.flush()

    ai_result = ai_analyze(
        message=transcript,
        emergency_id=resolved_emergency_id,
        relay_count=0,
        age_seconds=0,
        latitude=lat,
        longitude=lon,
    )

    outcome = process_sos_packet(db, packet, ai_result=ai_result)
    incident = outcome.incident

    db.add(IncidentAuditLog(
        incident_id=incident.id,
        action=AuditAction.CREATED if outcome.is_new_incident else AuditAction.MERGED,
        packet_id=packet.packet_id,
        detail=(
            "Voice SOS: transcribed from audio upload; authorised by a signed device "
            "request (Ed25519), arrived over internet rather than mesh relay"
        ),
    ))
    db.commit()

    return {
        "incident_id": incident.id,
        "emergency_id": resolved_emergency_id,
        "packet_id": packet.packet_id,
        "transcript": transcript,
        "ai_analysis_available": ai_result is not None,
        "sms_contacts_notified": outcome.sms_contacts_notified,
        **outcome.dedup.as_dict(),
        "note": (
            "Transcript is an English translation of the spoken message. "
            "This report arrived over the internet (authenticated by the device key), "
            "not through the signed mesh path."
        ),
    }


@router.get("/ingest/voice/status")
def voice_status():
    """
    Lets the mobile app check whether voice SOS is usable on this
    deployment BEFORE letting a user record something that can't be
    processed -- better than accepting a recording and failing after.
    """
    available = transcription_available()
    return {
        "available": available,
        "detail": (
            "Voice SOS is available."
            if available
            else "Voice SOS unavailable: requires openai-whisper package and system ffmpeg."
        ),
    }
