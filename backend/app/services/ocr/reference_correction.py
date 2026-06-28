import re
import unicodedata
from typing import Optional

from rapidfuzz import fuzz


def normalize_vietnamese(text: str) -> str:
    text = unicodedata.normalize("NFD", text.lower())
    text = "".join(c for c in text if unicodedata.category(c) != "Mn")
    return re.sub(r"[^a-z0-9\s]", "", text).strip()


def fuzzy_match_merchant(ocr_name: str, references: list[str], threshold: float = 80.0) -> Optional[str]:
    best_match = None
    best_score = 0.0
    normalized_ocr = normalize_vietnamese(ocr_name)

    for ref in references:
        score = fuzz.token_sort_ratio(normalized_ocr, normalize_vietnamese(ref))
        if score > best_score:
            best_score = score
            best_match = ref

    if best_score >= threshold:
        return best_match
    return None
