"""
SETU AI - Multilingual Embedding Similarity

Lexical similarity (difflib.SequenceMatcher, in duplicate_detector.py)
only catches near-identical wording. It misses paraphrases and, more
importantly, misses cross-language duplicates entirely - "Fire in
Block A" and "aag lag gayi Block A mein" describe the same incident
but share almost no overlapping characters, so difflib scores them low.

This module uses a small multilingual sentence-embedding model
(paraphrase-multilingual-MiniLM-L12-v2, ~120MB) that places English and
Hindi/Hinglish text describing the same thing close together in the
same embedding space, so cross-language and paraphrased duplicates get
caught too.

Soft dependency, same pattern as service/gemini_service.py's lazy
client: model load is attempted once, lazily, on first real use.
Importing this module never crashes anything, even with
sentence-transformers not installed or no internet to download the
model on first run - every function here returns None on failure
instead of raising, and duplicate_detector.py falls back to lexical
similarity whenever it gets None back.
"""

from typing import Optional

from config import EMBEDDING_MODEL_NAME
from utils.logger import get_logger

logger = get_logger(__name__)

_model = None
_load_attempted = False


def _get_model():
    """Lazy-load the embedding model once per process; never retries after a failed attempt."""
    global _model, _load_attempted
    if _model is not None:
        return _model
    if _load_attempted:
        return None  # already failed once this process - don't retry every call

    _load_attempted = True
    try:
        from sentence_transformers import SentenceTransformer
        _model = SentenceTransformer(EMBEDDING_MODEL_NAME)
        logger.info(f"Loaded multilingual embedding model: {EMBEDDING_MODEL_NAME}")
    except Exception as e:
        logger.warning(
            f"Embedding model unavailable ({e}); duplicate detection will fall back "
            "to lexical (difflib) text similarity only. Run "
            "`pip install -r requirements.txt` and ensure internet access on first "
            "run so the model can download, or set "
            "SETU_AI_EMBEDDING_DEDUP_ENABLED=false to silence this."
        )
        _model = None

    return _model


def get_embedding(text: str):
    """
    Returns the sentence embedding for text as a numpy array, or None if
    the embedding model isn't available. Encoding happens once per new
    incoming message in duplicate_detector.py - existing clusters reuse
    their cached embedding rather than being re-encoded every check.
    """
    model = _get_model()
    if model is None:
        return None
    try:
        return model.encode(text)
    except Exception as e:
        logger.warning(f"Embedding encode failed ({e}); falling back to lexical similarity.")
        return None


def cosine_similarity(vec_a, vec_b) -> float:
    import numpy as np
    a, b = np.asarray(vec_a), np.asarray(vec_b)
    denom = (np.linalg.norm(a) * np.linalg.norm(b))
    if denom == 0:
        return 0.0
    return float(np.dot(a, b) / denom)


def embedding_similarity(text1: str, text2: str) -> Optional[float]:
    """Convenience wrapper: cosine similarity between two texts' embeddings, or None if unavailable."""
    emb1, emb2 = get_embedding(text1), get_embedding(text2)
    if emb1 is None or emb2 is None:
        return None
    return cosine_similarity(emb1, emb2)


if __name__ == "__main__":
    # These will print None instead of a score if sentence-transformers
    # isn't installed or the model hasn't been downloaded - that's the
    # expected, non-crashing fallback behavior, not a bug.
    print("Fire in Block A / aag lag gayi Block A mein  ->",
          embedding_similarity("Fire in Block A", "aag lag gayi Block A mein"))
    print("Fire in Block A / Flood near the river       ->",
          embedding_similarity("Fire in Block A", "Flood near the river"))
