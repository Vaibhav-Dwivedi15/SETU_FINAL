"""
SETU AI - Duplicate Detection Engine

Compares a NEW incoming message against ALL still-active recent messages
(not just one hardcoded second message, which was the original bug -
should_process(text1, text2) could only ever compare two specific texts
you already had to know about, so it was never actually able to catch a
5th independent report of the same fire against the 4 that came before
it). This version maintains a rolling in-memory cluster list and checks
new messages against the whole active window.

v2.2 added geo: two reports only count as the same incident if they're
also within GEO_DEDUP_RADIUS_METERS of each other.

v2.3 adds multilingual embedding similarity on top of the original
lexical (difflib) similarity. Lexical similarity only catches
near-identical wording and completely misses cross-language duplicates
- "Fire in Block A" and "aag lag gayi Block A mein" describe the same
incident but share almost no overlapping characters. When the
embedding model (models/embedding_similarity.py) is available, it's
used instead of lexical matching; if it isn't (not installed, or no
internet to download it on first run), this falls back to the
original lexical-only behavior automatically - never crashes either
way. See config.EMBEDDING_DEDUP_ENABLED.

Author : SETU Team
Version : 2.3 (multilingual embedding similarity added, with lexical fallback)
"""

from dataclasses import dataclass, field
from difflib import SequenceMatcher
from math import atan2, cos, radians, sin, sqrt
import re
import time
from typing import Optional

from config import (
    EMBEDDING_DEDUP_ENABLED,
    EMBEDDING_SIMILARITY_THRESHOLD,
    GEO_DEDUP_RADIUS_METERS,
    SIMILARITY_THRESHOLD,
    TIME_WINDOW_SECONDS,
)
from models.embedding_similarity import cosine_similarity, get_embedding

EARTH_RADIUS_METERS = 6_371_000


@dataclass
class ClusterEntry:
    cluster_id: str
    normalized_text: str
    first_seen: float
    latitude: float = 0.0
    longitude: float = 0.0
    # Cached once when this cluster is created, so later comparisons
    # don't re-encode the same text over and over. None if the
    # embedding model wasn't available at the time this was created.
    embedding: Optional[object] = field(default=None, repr=False)


# NOTE: still an in-memory list - resets on restart, and will NOT stay
# consistent across multiple worker processes in a real deployment (each
# worker gets its own copy). Fine for a single-process demo/MVP; needs a
# shared store (Redis, or the actual backend DB) before real multi-worker use.
_CLUSTERS: list[ClusterEntry] = []


def normalize_message(message: str) -> str:
    """Lowercase, strip punctuation, collapse whitespace."""
    message = message.lower()
    message = re.sub(r"[^\w\s]", "", message)
    return " ".join(message.split())


def lexical_similarity(text1: str, text2: str) -> float:
    """Character-overlap similarity - the original difflib-based approach. Language-blind."""
    return SequenceMatcher(None, normalize_message(text1), normalize_message(text2)).ratio()


def _has_gps_fix(latitude: float, longitude: float) -> bool:
    """(0.0, 0.0) is the packet spec's documented no-GPS-fix fallback, not a real location."""
    return not (latitude == 0.0 and longitude == 0.0)


def haversine_distance_meters(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """Great-circle distance between two lat/long points, in meters."""
    lat1_r, lon1_r, lat2_r, lon2_r = map(radians, (lat1, lon1, lat2, lon2))
    d_lat = lat2_r - lat1_r
    d_lon = lon2_r - lon1_r
    a = sin(d_lat / 2) ** 2 + cos(lat1_r) * cos(lat2_r) * sin(d_lon / 2) ** 2
    c = 2 * atan2(sqrt(a), sqrt(1 - a))
    return EARTH_RADIUS_METERS * c


def _prune_expired() -> None:
    now = time.time()
    global _CLUSTERS
    _CLUSTERS = [c for c in _CLUSTERS if now - c.first_seen <= TIME_WINDOW_SECONDS]


def check_duplicate(
    message: str,
    emergency_id: str,
    latitude: float = 0.0,
    longitude: float = 0.0,
) -> dict:
    """
    Checks a new message against every still-active cluster, combining
    text similarity (embedding-based when available, lexical otherwise)
    with a geo-proximity check (see module docstring).

    Returns:
        {
          "is_duplicate": bool,
          "matched_cluster_id": str,
          "similarity": float,
          "match_method": "embedding" | "lexical",
          "distance_meters": float | None,
          "dedup_reason": str,   # Block 2: why (see below)
        }
    """
    _prune_expired()
    normalized = normalize_message(message)
    has_gps = _has_gps_fix(latitude, longitude)

    # Encode the incoming message once, up front - every existing cluster
    # already has its embedding cached from when it was created, so this
    # is the only encode call this function makes, not one per cluster.
    message_embedding = get_embedding(message) if EMBEDDING_DEDUP_ENABLED else None

    for cluster in _CLUSTERS:
        if message_embedding is not None and cluster.embedding is not None:
            score = cosine_similarity(message_embedding, cluster.embedding)
            threshold = EMBEDDING_SIMILARITY_THRESHOLD
            method = "embedding"
        else:
            score = lexical_similarity(normalized, cluster.normalized_text)
            threshold = SIMILARITY_THRESHOLD
            method = "lexical"

        if score < threshold:
            continue

        distance = None
        if has_gps and _has_gps_fix(cluster.latitude, cluster.longitude):
            distance = haversine_distance_meters(latitude, longitude, cluster.latitude, cluster.longitude)
            if distance > GEO_DEDUP_RADIUS_METERS:
                # Text/embedding matches, but too far apart to plausibly be
                # the same incident - keep checking other clusters.
                continue

        return {
            "is_duplicate": True,
            "matched_cluster_id": cluster.cluster_id,
            "similarity": round(float(score), 2),
            "match_method": method,
            "distance_meters": round(distance, 1) if distance is not None else None,
            # Block 2: explainable decision. "location_unverified" = at least one
            # side had no GPS fix, so this merge rests on text similarity + time only.
            "dedup_reason": "text_and_geo_match" if distance is not None else "text_match_location_unverified",
        }

    _CLUSTERS.append(
        ClusterEntry(
            cluster_id=emergency_id,
            normalized_text=normalized,
            first_seen=time.time(),
            latitude=latitude,
            longitude=longitude,
            embedding=message_embedding,
        )
    )
    return {
        "is_duplicate": False,
        "matched_cluster_id": emergency_id,
        "similarity": 0.0,
        "match_method": "embedding" if message_embedding is not None else "lexical",
        "distance_meters": None,
        "dedup_reason": "no_similar_recent_report",
    }


def reset_clusters() -> None:
    """Test helper only - clears in-memory state between test runs."""
    global _CLUSTERS
    _CLUSTERS = []


if __name__ == "__main__":
    reset_clusters()
    print(check_duplicate("Fire in Block A", "e1", latitude=28.6139, longitude=77.2090))
    # Cross-language paraphrase, same incident -> catches this ONLY if the
    # embedding model is installed/downloaded; falls back to lexical
    # (which will likely miss it) otherwise.
    print(check_duplicate("aag lag gayi Block A mein madad karo", "e2", latitude=28.6141, longitude=77.2092))
    print(check_duplicate("Flood near the river", "e3", latitude=28.6139, longitude=77.2090))
