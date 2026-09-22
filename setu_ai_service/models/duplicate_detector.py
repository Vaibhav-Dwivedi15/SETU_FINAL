"""
SETU AI - Safe Geolocation-Aware Duplicate Detection Engine
Prevents malicious or accidental cross-incident merging.
"""

from difflib import SequenceMatcher
from dataclasses import dataclass
import math
import re
import time
from typing import Optional, Tuple, Dict, Any

from config import SIMILARITY_THRESHOLD, TIME_WINDOW_SECONDS

# Standard spatial proximity threshold for emergency clustering (500 meters)
MAX_DISTANCE_KM = 0.5


@dataclass
class ClusterEntry:
    cluster_id: str
    normalized_text: str
    incident_type: str
    first_seen: float
    latitude: Optional[float] = None
    longitude: Optional[float] = None


_CLUSTERS: list[ClusterEntry] = []


def haversine_distance_km(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """Calculate great-circle distance between two points in kilometers."""
    R = 6371.0  # Earth radius in km
    dlat = math.radians(lat2 - lat1)
    dlon = math.radians(lon2 - lon1)
    a = (
        math.sin(dlat / 2) ** 2
        + math.cos(math.radians(lat1))
        * math.cos(math.radians(lat2))
        * math.sin(dlon / 2) ** 2
    )
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))
    return R * c


def normalize_message(message: str) -> str:
    message = message.lower()
    message = re.sub(r"[^\w\s]", "", message)
    return " ".join(message.split())


def _prune_expired() -> None:
    now = time.time()
    global _CLUSTERS
    _CLUSTERS = [c for c in _CLUSTERS if now - c.first_seen <= TIME_WINDOW_SECONDS]


def check_duplicate(
    message: str,
    emergency_id: str,
    incident_type: str = "Unknown",
    latitude: Optional[float] = None,
    longitude: Optional[float] = None,
) -> Dict[str, Any]:
    """
    Checks incoming message against active clusters with deterministic guards:
    1. Time window constraint
    2. Incident type consistency
    3. Strict geographic proximity (<= 500m)
    4. Text similarity score
    """
    _prune_expired()
    normalized = normalize_message(message)

    for cluster in _CLUSTERS:
        # Guard 1: Category Mismatch Guard
        if (
            incident_type != "Unknown"
            and cluster.incident_type != "Unknown"
            and incident_type != cluster.incident_type
        ):
            continue

        # Guard 2: Geographic Boundary Guard
        if (
            latitude is not None
            and longitude is not None
            and cluster.latitude is not None
            and cluster.longitude is not None
        ):
            dist = haversine_distance_km(latitude, longitude, cluster.latitude, cluster.longitude)
            if dist > MAX_DISTANCE_KM:
                # Outside safety radius — never merge even if message is identical!
                continue

        # Guard 3: Semantic/Text Similarity
        score = SequenceMatcher(None, normalized, cluster.normalized_text).ratio()
        if score >= SIMILARITY_THRESHOLD:
            return {
                "is_duplicate": True,
                "matched_cluster_id": cluster.cluster_id,
                "similarity": round(score, 2),
                "reason": f"Merged into cluster {cluster.cluster_id} (Similarity: {round(score, 2)})",
            }

    # Register new cluster
    _CLUSTERS.append(
        ClusterEntry(
            cluster_id=emergency_id,
            normalized_text=normalized,
            incident_type=incident_type,
            first_seen=time.time(),
            latitude=latitude,
            longitude=longitude,
        )
    )

    return {
        "is_duplicate": False,
        "matched_cluster_id": emergency_id,
        "similarity": 0.0,
        "reason": "New distinct incident registered",
    }


def reset_clusters() -> None:
    global _CLUSTERS
    _CLUSTERS = []
