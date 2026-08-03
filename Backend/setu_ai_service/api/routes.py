import os
import tempfile
from pathlib import Path

from fastapi import APIRouter, File, Form, HTTPException, UploadFile
from pydantic import BaseModel

from models.pipeline import process_message
from models.response_models import TriageResponse
from service.voice_service import transcribe_audio

router = APIRouter()


class EmergencyRequest(BaseModel):
    emergency_id: str
    message: str
    relay_count: int = 0
    age_seconds: int = 0
    # Matches the mesh packet's own field names exactly (Section 3 of the
    # project handoff). Defaults to 0.0, the packet spec's documented
    # no-GPS-fix fallback - check_duplicate() knows to treat that as
    # "no usable location" rather than a real position.
    latitude: float = 0.0
    longitude: float = 0.0


@router.get("/")
def home():
    return {"project": "SETU AI Service", "status": "Running"}


@router.post("/analyze", response_model=TriageResponse)
def analyze(request: EmergencyRequest):
    return process_message(
        message=request.message,
        relay_count=request.relay_count,
        age_seconds=request.age_seconds,
        emergency_id=request.emergency_id,
        latitude=request.latitude,
        longitude=request.longitude,
    )


@router.post("/analyze-voice", response_model=TriageResponse)
async def analyze_voice(
    file: UploadFile = File(...),
    emergency_id: str = Form(...),
    relay_count: int = Form(0),
    age_seconds: int = Form(0),
    latitude: float = Form(0.0),
    longitude: float = Form(0.0),
):
    """
    Same as /analyze, but the message comes from an uploaded audio file
    instead of text. The audio is transcribed (and translated to English -
    see service/voice_service.py for why) and the resulting text is run
    through the exact same pipeline /analyze uses, so urgency, incident
    type, dedup, confidence, and explanation all work identically.
    """
    suffix = Path(file.filename).suffix or ".wav"
    with tempfile.NamedTemporaryFile(delete=False, suffix=suffix) as tmp:
        contents = await file.read()
        tmp.write(contents)
        tmp_path = tmp.name

    try:
        text = transcribe_audio(tmp_path)
    finally:
        # Always clean up the temp file, even if transcription raised.
        os.unlink(tmp_path)

    if not text:
        raise HTTPException(
            status_code=422,
            detail=(
                "Could not transcribe audio. The file may be silent, corrupted, "
                "in an unsupported format, or the Whisper model may not be "
                "installed/available on this server."
            ),
        )

    return process_message(
        message=text,
        relay_count=relay_count,
        age_seconds=age_seconds,
        emergency_id=emergency_id,
        latitude=latitude,
        longitude=longitude,
    )
