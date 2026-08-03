"""
SETU AI - Emergency AI Service

This service acts as the main interface
between the application and the AI models.

Author : SETU Team
Version : 2.2 (fixed: emergency_id was missing, causing every call to
                     crash with TypeError since process_message() requires it;
                     geo-aware dedup: latitude/longitude now forwarded through
                     to the pipeline, matching the packet spec's field
                     names and its 0.0/0.0 no-GPS-fix fallback)
"""

from models.pipeline import process_message


def analyze_emergency(
    message: str,
    emergency_id: str,
    relay_count: int = 0,
    age_seconds: int = 0,
    latitude: float = 0.0,
    longitude: float = 0.0,
) -> dict:
    """
    Analyze an emergency message using
    the complete SETU AI pipeline.
    """

    result = process_message(
        message=message,
        emergency_id=emergency_id,
        relay_count=relay_count,
        age_seconds=age_seconds,
        latitude=latitude,
        longitude=longitude,
    )

    return result


if __name__ == "__main__":
    result = analyze_emergency(
        "Fire in my building",
        emergency_id="test-e1",
        relay_count=2,
        age_seconds=30,
        latitude=28.6139,
        longitude=77.2090,
    )

    print(result)
