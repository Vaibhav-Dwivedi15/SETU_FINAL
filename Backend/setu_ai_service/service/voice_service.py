"""
SETU AI - Voice Message Transcription

Converts an audio distress message into text using OpenAI Whisper
(offline, matches the project's no-SIM/no-data operating philosophy -
same reasoning as models/embedding_similarity.py's local embedding
model).

Design decision: uses Whisper's TRANSLATE task, not TRANSCRIBE.
  - transcribe would return text in whatever language was spoken - a
    Hindi voice message would come back in Devanagari script, which
    the rest of this pipeline's Hinglish keyword lists (Roman script)
    do NOT match. That would silently break urgency/incident detection
    for anyone speaking Hindi rather than typing Hinglish.
  - translate always returns English text regardless of the spoken
    language, which lines up with this pipeline's most complete
    keyword coverage. The tradeoff: some Hinglish-specific phrasing
    nuance is lost in translation. English-input speech is unaffected
    (translate is effectively a no-op for English audio).
  - This is a deliberate MVP simplification, documented here rather
    than hidden. A more complete version would also keep the
    original-language transcript and feed it through a transliteration
    step so the Hinglish keyword lists still get a chance to match on
    the source wording.

Model is lazy-loaded once per process (same soft-dependency pattern as
models/embedding_similarity.py) - first call downloads the Whisper
"base" model (~150MB) from OpenAI, cached locally after that. Needs
ffmpeg installed on the system (not a pip package - see project setup
notes / README).

Author : SETU Team
Version : 1.0
"""

from pathlib import Path
from typing import Optional

from utils.logger import get_logger

logger = get_logger(__name__)

_model = None
_load_attempted = False


def _get_model():
    """Lazy-load Whisper once per process; never retries after a failed attempt."""
    global _model, _load_attempted
    if _model is not None:
        return _model
    if _load_attempted:
        return None

    _load_attempted = True
    try:
        import whisper
        _model = whisper.load_model("base")
        logger.info("Loaded Whisper 'base' speech-to-text model")
    except Exception as e:
        logger.warning(
            f"Whisper model unavailable ({e}); voice transcription will fail "
            "until this is resolved (check ffmpeg is installed and "
            "`pip install -r requirements.txt` has run)."
        )
        _model = None

    return _model


def transcribe_audio(file_path: str) -> Optional[str]:
    """
    Transcribes and translates a voice message to English text.

    Returns the transcribed text, or None if the model isn't available,
    the file doesn't exist, or transcription failed - callers MUST
    handle None explicitly rather than assuming a string (e.g. return
    a clear error to the client instead of silently processing "None"
    as if it were a real message).
    """
    model = _get_model()
    if model is None:
        return None

    if not Path(file_path).exists():
        logger.warning(f"Audio file not found: {file_path}")
        return None

    try:
        result = model.transcribe(file_path, task="translate")
        text = result.get("text", "").strip()
        detected_language = result.get("language", "unknown")
        logger.info(f"Transcribed audio (detected source language: {detected_language}): \"{text}\"")
        return text if text else None
    except Exception as e:
        logger.warning(f"Transcription failed for {file_path}: {e}")
        return None


if __name__ == "__main__":
    import sys
    if len(sys.argv) < 2:
        print("Usage: python -m service.voice_service <path-to-audio-file>")
    else:
        text = transcribe_audio(sys.argv[1])
        print(f"Transcribed text: {text}")
