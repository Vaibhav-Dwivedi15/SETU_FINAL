"""
SETU AI - Gemini Prompt Templates

Extracted from gemini_service.py so the prompt can be tuned/versioned
without touching the API-calling code.
"""

EMERGENCY_ANALYSIS_PROMPT = """You are an emergency response AI.

Analyze the emergency message below.

Message:
{message}

Return ONLY:

Incident Type:
Severity:
Short Summary:
"""
