"""
Wrapper around setu_ai_service's Whisper voice transcription.

Mirrors app/services/ai_analysis_service.py exactly in structure and
failure posture -- same sys.path shim (see app/utils/setu_ai_import_guard.py),
same "never raises, returns None on any failure" contract. Read that
file's docstring first if this one's import dance looks odd.

WHAT THE AI SERVICE ACTUALLY DOES (confirmed by reading
setu_ai_service/service/voice_service.py directly, not assumed):
  - Uses Whisper's TRANSLATE task, not TRANSCRIBE. Any spoken language
    comes back as ENGLISH text. This is deliberate on the AI side: the
    downstream Hinglish keyword lists are Roman-script, so a Devanagari
    transcript would silently fail to match them.
  - This means the multilingual story here is REAL but one-directional:
    a user can speak Hindi/Bengali/Tamil/etc. and the pipeline
    understands it. It does NOT preserve the original-language wording.
    Do not claim the system "stores the message in the user's language"
    -- it doesn't, and the AI team documented that tradeoff themselves.
  - Requires the `openai-whisper` package AND ffmpeg installed on the
    system (ffmpeg is not a pip package). On a fresh Render instance
    neither is present, so transcription will return None there until
    that's provisioned. That is a real deployment gap, flagged not hidden.
  - First call downloads the Whisper "base" model (~150MB) and caches it.
    That first request will be slow.
"""
import logging

from app.utils.setu_ai_import_guard import ensure_setu_ai_service_importable

ensure_setu_ai_service_importable()

logger = logging.getLogger("setu.voice")


def transcribe(file_path: str) -> str | None:
    """
    Returns English transcript text, or None if transcription was
    unavailable or failed for any reason. Callers MUST handle None
    explicitly -- never treat it as an empty message and process it as
    if it were a real distress report.
    """
    try:
        from service.voice_service import transcribe_audio  # setu_ai_service's own layout
    except Exception:
        logger.exception("setu_ai_service voice module import failed -- transcription unavailable")
        return None

    try:
        return transcribe_audio(file_path)
    except Exception:
        logger.exception("Voice transcription raised for %s", file_path)
        return None


def transcription_available() -> bool:
    """
    Best-effort check that the voice path is usable, so an endpoint can
    return a clear 503 instead of accepting an upload it can't process.
    Only verifies the import succeeds -- it does not load the Whisper
    model (that's a ~150MB download on first use) or check for ffmpeg,
    so a True here still isn't a guarantee of a successful transcription.
    """
    try:
        from service.voice_service import transcribe_audio  # noqa: F401
        import whisper  # noqa: F401
        return True
    except Exception:
        return False
