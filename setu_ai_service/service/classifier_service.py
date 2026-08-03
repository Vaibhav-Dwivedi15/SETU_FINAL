"""
SETU AI - Classifier Service

Uses Gemini Service to classify
emergency messages.

Author : SETU Team
Version : 2.0
"""

from service.gemini_service import analyze_with_gemini


def classify_emergency(message: str) -> str:
    """
    Classify an emergency message using Gemini.
    """

    return analyze_with_gemini(message)


if __name__ == "__main__":
    result = classify_emergency(
        "Fire in my building and people are trapped."
    )

    print(result)
