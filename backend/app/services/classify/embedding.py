"""Multi-field feature vector for PVC-Class (Phase 2: sentence-transformer + metadata)."""

import hashlib
import logging
from datetime import date, datetime
from functools import lru_cache

import numpy as np

from app.config import settings

logger = logging.getLogger(__name__)

EMBEDDING_DIM = 768
AMOUNT_BUCKETS = [0, 50000, 100000, 200000, 500000, 1000000, float("inf")]


def _amount_bucket(amount: float) -> int:
    for i, upper in enumerate(AMOUNT_BUCKETS[1:]):
        if amount <= upper:
            return i
    return len(AMOUNT_BUCKETS) - 2


def _time_bucket(dt: date | datetime) -> int:
    hour = dt.hour if isinstance(dt, datetime) else 12
    if 5 <= hour < 11:
        return 0
    if 11 <= hour < 17:
        return 1
    if 17 <= hour < 22:
        return 2
    return 3


def _weekday_bucket(dt: date | datetime) -> int:
    d = dt.date() if isinstance(dt, datetime) else dt
    return 0 if d.weekday() < 5 else 1


def _metadata_vector(amount: float, transaction_date: date | datetime) -> np.ndarray:
    """One-hot metadata appended to text embedding (amount/time/weekday buckets)."""
    meta = np.zeros(16, dtype=np.float32)
    meta[_amount_bucket(amount)] = 1.0
    meta[6 + _time_bucket(transaction_date)] = 1.0
    meta[10 + _weekday_bucket(transaction_date)] = 1.0
    return meta


def build_feature_text(merchant: str | None, items: list | None) -> str:
    parts = [merchant or ""]
    if items:
        for item in items:
            name = item.get("name") if isinstance(item, dict) else getattr(item, "name", "")
            parts.append(str(name))
    return " ".join(p for p in parts if p).strip() or "unknown"


@lru_cache(maxsize=1)
def _load_sentence_model():
    if not settings.use_sentence_embeddings:
        return None
    try:
        from sentence_transformers import SentenceTransformer

        logger.info("Loading sentence-transformer: %s", settings.embedding_model_name)
        return SentenceTransformer(settings.embedding_model_name)
    except Exception as exc:
        logger.warning("Sentence-transformer unavailable, using hash fallback: %s", exc)
        return None


def _hash_embedding(text: str, dim: int = EMBEDDING_DIM) -> np.ndarray:
    seed = int(hashlib.sha256(text.encode()).hexdigest(), 16) % (2**32)
    rng = np.random.default_rng(seed)
    vec = rng.standard_normal(dim).astype(np.float32)
    return vec / (np.linalg.norm(vec) + 1e-8)


def _encode_text(text: str) -> np.ndarray:
    model = _load_sentence_model()
    if model is None:
        return _hash_embedding(text)

    raw = model.encode(text, normalize_embeddings=True)
    vec = np.array(raw, dtype=np.float32)
    if vec.shape[0] < EMBEDDING_DIM:
        padded = np.zeros(EMBEDDING_DIM, dtype=np.float32)
        padded[: vec.shape[0]] = vec
        vec = padded
    elif vec.shape[0] > EMBEDDING_DIM:
        vec = vec[:EMBEDDING_DIM]
    norm = np.linalg.norm(vec)
    return vec / norm if norm > 0 else vec


def build_feature_vector(
    merchant: str | None,
    items: list | None,
    amount: float,
    transaction_date: date | datetime,
    dim: int = EMBEDDING_DIM,
) -> list[float]:
    text = build_feature_text(merchant, items)
    text_vec = _encode_text(text)

    meta = _metadata_vector(amount, transaction_date)
    # Blend metadata into last dimensions for multi-field signal
    blended = text_vec.copy()
    blended[-16:] = (blended[-16:] * 0.7) + (meta * 0.3)
    norm = np.linalg.norm(blended)
    if norm > 0:
        blended = blended / norm
    return blended.tolist()
