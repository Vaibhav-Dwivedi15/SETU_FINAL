"""
SETU AI - Gemini Service

Optional enhancement layer — see config.GEMINI_ENABLED. Client
initialization is lazy (only happens on the first real call), so simply
importing this module never crashes the service even with no API key
configured. The previous version built the client at import time, which
meant any accidental import anywhere in the codebase would crash the
whole app if .env was missing — that's fixed here.
"""

import os
from pathlib import Path

from dotenv import load_dotenv

from config import GEMINI_MODEL_NAME
from prompts.emergency_prompt import EMERGENCY_ANALYSIS_PROMPT

BASE_DIR = Path(__file__).resolve().parents[1]
load_dotenv(BASE_DIR / ".env")

_client = None


def _get_client():
    global _client
    if _client is None:
        from google import genai
        api_key = os.getenv("GEMINI_API_KEY")
        if not api_key:
            raise ValueError("GEMINI_API_KEY not set — only required when Gemini is enabled.")
        _client = genai.Client(api_key=api_key)
    return _client


def analyze_with_gemini(message: str) -> str:
    """
    Analyze an emergency message using Gemini. Only ever called from
    pipeline.py when config.GEMINI_ENABLED is true AND the rule-based
    classifier returned "Unknown" — never on the default critical path.
    """
    prompt = EMERGENCY_ANALYSIS_PROMPT.format(message=message)
    try:
        client = _get_client()
        response = client.models.generate_content(model=GEMINI_MODEL_NAME, contents=prompt)
        return response.text
    except Exception as e:
        return f"Gemini Error: {e}"
