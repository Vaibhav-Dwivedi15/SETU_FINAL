"""
SETU AI - Duplicate Detection Engine

Compares a NEW incoming message against ALL still-active recent messages
(not just one hardcoded second message, which was the original bug —
should_process(text1, text2) could only ever compare two specific texts
you already had to know about, so it was never actually able to catch a
5th independent report of the same fire against the 4 that came before
it). This version maintains a rolling in-memory cluster list and checks
new messages against the whole active window.

Author : SETU Team
Version : 2.1 (duplicate-comparison bug fixed)
"""

from difflib import SequenceMatcher
from dataclasses import dataclass
import re
import time

from config import SIMILARITY_THRESHOLD, TIME_WINDOW_SECONDS


@dataclass
class ClusterEntry:
    cluster_id: str
    normalized_text: str
    first_seen: float


# NOTE: still an in-memory list — resets on restart, and will NOT stay
# consistent across multiple worker processes in a real deployment (each
# worker gets its own copy). Fine for a single-process demo/MVP; needs a
# shared store (Redis, or the actual backend DB) before real multi-worker use.
_CLUSTERS: list[ClusterEntry] = []


def normalize_message(message: str) -> str:
    """Lowercase, strip punctuation, collapse whitespace."""
    message = message.lower()
    message = re.sub(r"[^\w\s]", "", message)
    return " ".join(message.split())


def similarity(text1: str, text2: str) -> float:
    return SequenceMatcher(None, normalize_message(text1), normalize_message(text2)).ratio()


def _prune_expired() -> None:
    now = time.time()
    global _CLUSTERS
    _CLUSTERS = [c for c in _CLUSTERS if now - c.first_seen <= TIME_WINDOW_SECONDS]


def check_duplicate(message: str, emergency_id: str) -> dict:
    """
    Checks a new message against every still-active cluster.

    Returns:
        {
          "is_duplicate": bool,
          "matched_cluster_id": str,  # emergency_id to treat this report
                                       # as belonging to
          "similarity": float
        }
    """
    _prune_expired()
    normalized = normalize_message(message)

    for cluster in _CLUSTERS:
        score = SequenceMatcher(None, normalized, cluster.normalized_text).ratio()
        if score >= SIMILARITY_THRESHOLD:
            return {
                "is_duplicate": True,
                "matched_cluster_id": cluster.cluster_id,
                "similarity": round(score, 2),
            }

    _CLUSTERS.append(
        ClusterEntry(cluster_id=emergency_id, normalized_text=normalized, first_seen=time.time())
    )
    return {"is_duplicate": False, "matched_cluster_id": emergency_id, "similarity": 0.0}


def reset_clusters() -> None:
    """Test helper only — clears in-memory state between test runs."""
    global _CLUSTERS
    _CLUSTERS = []


if __name__ == "__main__":
    reset_clusters()
    print(check_duplicate("Fire in Block A", "e1"))
    print(check_duplicate("Building fire in Block A", "e2"))
    print(check_duplicate("Flood near the river", "e3"))
