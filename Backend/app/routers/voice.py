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
Packets arriving via /ingest are Ed25519-signed and verified. A voice
upload arriving here is NOT signed -- there is no signature over an
audio file in the frozen packet spec, and inventing one here would be a
spec change requiring team-lead sign-off. That means this route is
LESS trusted than /ingest, and incidents created through it are marked
as such in their audit trail. Do not present voice SOS as having the
same cryptographic guarantees as the mesh path. It doesn't.
"""
import logging
import os
import tempfile
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile
from sqlalchemy.orm import Session

from app.db.base import get_db
from app.models.audit_log import IncidentAuditLog, AuditAction
from app.models.packet import RawPacket, PacketStatus
from app.schemas.packet import PacketIn, PacketType, PriorityLevel
from app.services.ai_analysis_service import analyze as ai_analyze
from app.services.incident_service import handle_sos_packet
from app.services.voice_transcription_service import transcribe, transcription_available

logger = logging.getLogger("setu.voice_ingest")

router = APIRouter()

# Whisper handles common audio containers; this cap exists so a stray
# large upload can't exhaust the instance's disk or memory. 25MB is far
# more than any realistic distress recording.
MAX_AUDIO_BYTES = 25 * 1024 * 1024

ALLOWED_SUFFIXES = {".wav", ".mp3", ".m4a", ".ogg", ".oga", ".webm", ".flac", ".aac", ".mp4"}


@router.post("/ingest/voice")
async def ingest_voice_sos(
    file: UploadFile = File(..., description="Audio recording of the distress message"),
    sender_id: str = Form(..., description="Device's hex-encoded Ed25519 public key"),
    latitude: float = Form(0.0),
    longitude: float = Form(0.0),
    priority: Optional[str] = Form(None, description="low | medium | high | critical"),
    emergency_id: Optional[str] = Form(None),
    db: Session = Depends(get_db),
):
    """
    Transcribes an uploaded audio file and runs the resulting text
    through the exact same emergency pipeline a typed SOS uses -- AI
    triage, duplicate detection, incident creation/merge, emergency
    contact SMS, and the government notification adapter all behave
    identically, because they all operate on the transcribed text.

    Returns the created/merged incident id plus the transcript, so the
    app can show the user what was actually understood from their
    recording -- important, since a mis-transcription in an emergency is
    something the user should be able to see and correct.
    """
    if not transcription_available():
        raise HTTPException(
            status_code=503,
            detail=(
                "Voice transcription is not available on this server. It requires the "
                "openai-whisper package and a system ffmpeg install; neither is present "
                "by default on a fresh deployment."
            ),
        )

    suffix = Path(file.filename or "").suffix.lower() or ".wav"
    if suffix not in ALLOWED_SUFFIXES:
        raise HTTPException(
            status_code=415,
            detail=f"Unsupported audio format '{suffix}'. Supported: {', '.join(sorted(ALLOWED_SUFFIXES))}",
        )

    contents = await file.read()
    if len(contents) == 0:
        raise HTTPException(status_code=400, detail="Uploaded audio file is empty.")
    if len(contents) > MAX_AUDIO_BYTES:
        raise HTTPException(
            status_code=413,
            detail=f"Audio file too large ({len(contents)} bytes). Limit is {MAX_AUDIO_BYTES} bytes.",
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
            logger.warning("Could not delete temp audio file %s", tmp_path)

    if not transcript:
        raise HTTPException(
            status_code=422,
            detail=(
                "Could not transcribe the audio. It may be silent, corrupted, or in an "
                "unsupported encoding. Try recording again, or send a typed message instead."
            ),
        )

    resolved_emergency_id = emergency_id or f"voice-{uuid.uuid4().hex[:12]}"
    now = datetime.now(timezone.utc)

    # Build a PacketIn so the rest of the pipeline sees exactly the shape
    # it already handles. hop_count=0 is truthful: this report did not
    # travel through the mesh, it arrived directly over the internet.
    # signature is an explicit marker rather than a fake value -- see the
    # module docstring on why this path is deliberately less trusted.
    packet = PacketIn(
        packet_id=f"voice-{uuid.uuid4().hex}",
        sender_id=sender_id,
        type=PacketType.EMERGENCY,
        timestamp=now.isoformat(),
        nonce=uuid.uuid4().hex,
        ttl=0,
        hop_count=0,
        protocol_version=1,
        signature="UNSIGNED_VOICE_UPLOAD",
        emergency_id=resolved_emergency_id,
        latitude=latitude,
        longitude=longitude,
        message=transcript,
        priority=PriorityLevel(priority.lower()) if priority and priority.lower() in {
            "low", "medium", "high", "critical"
        } else None,
    )

    # Store the raw record first, same as /ingest does, so there's
    # evidence of the report independent of what happens downstream.
    # Status is VALIDATED (it was accepted and processed) -- but the
    # signature field above and the audit note below both record that
    # this arrived unsigned.
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
        latitude=latitude,
        longitude=longitude,
    )

    incident = handle_sos_packet(db, packet, ai_result=ai_result)

    # Explicit audit entry marking the provenance and trust level of this
    # report. handle_sos_packet already logged a CREATED or MERGED entry
    # for this packet; this adds the provenance detail that would
    # otherwise be invisible on the dashboard.
    #
    # The action is READ BACK from the entry handle_sos_packet just wrote
    # rather than guessed. An earlier version of this used
    # `AuditAction.MERGED if incident else AuditAction.CREATED`, which was
    # simply wrong -- handle_sos_packet always returns a truthy Incident
    # (it either found or created one), so that ternary could never
    # produce CREATED and every voice report would have been mislabelled
    # as a merge in the audit trail.
    origin_entry = (
        db.query(IncidentAuditLog)
        .filter(
            IncidentAuditLog.incident_id == incident.id,
            IncidentAuditLog.packet_id == packet.packet_id,
        )
        .order_by(IncidentAuditLog.created_at.desc())
        .first()
    )

    db.add(IncidentAuditLog(
        incident_id=incident.id,
        action=origin_entry.action if origin_entry else AuditAction.CREATED,
        packet_id=packet.packet_id,
        detail=(
            "Voice SOS: transcribed from audio upload (unsigned, arrived over internet "
            "rather than mesh relay)"
        ),
    ))
    db.commit()

    return {
        "incident_id": incident.id,
        "emergency_id": resolved_emergency_id,
        "packet_id": packet.packet_id,
        "transcript": transcript,
        "ai_analysis_available": ai_result is not None,
        "note": (
            "Transcript is an English translation of the spoken message. "
            "This report arrived unsigned over the internet, not through the signed mesh path."
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
