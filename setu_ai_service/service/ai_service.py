"""
SETU AI - Emergency AI Service

This service acts as the main interface
between the application and the AI models.

Author : SETU Team
Version : 2.0
"""

from models.pipeline import process_message


def analyze_emergency(
    message: str,
    relay_count: int = 0,
    age_seconds: int = 0
) -> dict:
    """
    Analyze an emergency message using
    the complete SETU AI pipeline.
    """

    result = process_message(
        message=message,
        relay_count=relay_count,
        age_seconds=age_seconds
    )

    return result


if __name__ == "__main__":
    result = analyze_emergency(
        "Fire in my building",
        relay_count=2,
        age_seconds=30
    )

    print(result)