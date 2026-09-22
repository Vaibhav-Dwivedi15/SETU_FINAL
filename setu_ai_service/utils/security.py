"""
SETU AI - Security & Sanitization Layer
Guards against prompt injection, adversarial overrides, and input abuse.
"""

import re
from typing import Tuple, List

# Maximum allowed characters for an emergency packet message
MAX_MESSAGE_LENGTH = 500

# Known Prompt Injection / Override patterns
INJECTION_PATTERNS = [
    r"ignore\s+(all\s+)?(previous|prior)\s+(instructions|prompts|rules)",
    r"disregard\s+(all\s+)?(previous|prior)",
    r"you\s+are\s+now\s+a",
    r"system\s+prompt",
    r"override\s+priority",
    r"set\s+priority\s+to\s+(low|zero)",
    r"mark\s+as\s+not\s+duplicate",
    r"do\s+not\s+dispatch",
    r"<script.*?>",
    r"```(python|bash|sh|json)?",
]


def sanitize_and_audit_input(raw_message: str) -> Tuple[str, bool, List[str]]:
    """
    Sanitizes message and detects potential adversarial attempts.

    Returns:
        (sanitized_text, is_flagged, threat_reasons)
    """
    if not raw_message or not raw_message.strip():
        return "", False, ["Empty message"]

    # 1. Length bounding (Buffer exhaustion defense)
    sanitized = raw_message.strip()
    if len(sanitized) > MAX_MESSAGE_LENGTH:
        sanitized = sanitized[:MAX_MESSAGE_LENGTH]

    threats = []
    is_flagged = False

    # 2. Check for Prompt Injection patterns
    lower_text = sanitized.lower()
    for pattern in INJECTION_PATTERNS:
        if re.search(pattern, lower_text):
            is_flagged = True
            threats.append(f"Prompt injection detected: matches '{pattern}'")

    # 3. Strip suspicious control characters
    sanitized = re.sub(r"[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]", "", sanitized)

    return sanitized, is_flagged, threats
