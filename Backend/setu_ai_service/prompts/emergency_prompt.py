"""
SETU AI - Gemini Prompt Templates

Extracted from gemini_service.py so the prompt can be tuned/versioned
without touching the API-calling code.

The response format is deliberately constrained to a fixed vocabulary
(exact incident-type and severity words) rather than free text. Gemini
is only ever consulted when the rule engine already returned "Unknown" -
its whole job is to hand back something the rest of the pipeline can
actually use to override that "Unknown", not just a paragraph a human
has to read separately. See service/gemini_service.py's
parse_gemini_response() for the matching parser.
"""

INCIDENT_TYPES = [
    "Fire", "Medical", "Accident", "Flood",
    "Building Collapse", "Earthquake", "Women Safety", "Unknown",
]

EMERGENCY_ANALYSIS_PROMPT = """You are an emergency response triage assistant.

Analyze the emergency message below and classify it. Respond in EXACTLY
this format, with no extra text before or after:

Incident Type: <one of: Fire, Medical, Accident, Flood, Building Collapse, Earthquake, Women Safety, Unknown>
Severity: <one of: Critical, High, Medium, Low>
Short Summary: <one sentence, max 20 words>

Message:
{message}
"""
