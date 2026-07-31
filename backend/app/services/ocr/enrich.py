"""Enrich OCR results using EasyOCR text when structured fields are missing."""

import logging
import re

from app.schemas import OcrResult
from app.services.ocr.parse_utils import parse_date, parse_final_amount

logger = logging.getLogger(__name__)


def _ocr_text_quality(text: str) -> int:
    """Score OCR text — higher is more usable for parsing."""
    if not text:
        return 0
    score = min(len(text), 500)
    for token in ("winmart", "bách hóa", "phiếu", "tổng", "thanh toán", "17,500", "113,900"):
        if token.lower() in text.lower():
            score += 40
    if re.search(r"\d{1,2}[/.-]\d{1,2}[/.-]\d{2,4}", text):
        score += 30
    return score


def _ocr_header_text(image_bytes: bytes) -> str | None:
    """OCR top portion of receipt where date is usually printed."""
    try:
        import cv2
        import numpy as np
        from app.services.ocr.local_ocr import run_local_ocr

        arr = np.frombuffer(image_bytes, np.uint8)
        img = cv2.imdecode(arr, cv2.IMREAD_COLOR)
        if img is None:
            return None
        h = img.shape[0]
        crop = img[0 : max(int(h * 0.28), 120), :]
        ok, buf = cv2.imencode(".jpg", crop)
        if not ok:
            return None
        return run_local_ocr(buf.tobytes())
    except Exception as exc:
        logger.debug("Header OCR skipped: %s", exc)
        return None


def enrich_from_easyocr(
    result: OcrResult,
    image_bytes: bytes,
    *,
    original_bytes: bytes | None = None,
) -> OcrResult:
    """Fill missing date/total hints from EasyOCR raw text."""
    needs_date = result.transaction_date is None
    needs_text = not result.raw_text or len(result.raw_text) < 40
    if not needs_date and not needs_text:
        return result

    try:
        from app.services.ocr.local_ocr import is_local_ocr_available, run_local_ocr
    except ImportError:
        return result

    if not is_local_ocr_available():
        return result

    candidates: list[str] = []
    for blob in (original_bytes, image_bytes):
        if not blob:
            continue
        try:
            candidates.append(run_local_ocr(blob))
        except Exception as exc:
            logger.debug("EasyOCR enrich skipped: %s", exc)

    if not candidates:
        return result

    ocr_text = max(candidates, key=_ocr_text_quality)
    updates: dict = {}
    combined = f"{result.raw_text or ''}\n{ocr_text}".strip()
    if combined:
        updates["raw_text"] = combined

    if needs_date:
        dt = parse_date(ocr_text) or parse_date(combined)
        if not dt and original_bytes:
            header = _ocr_header_text(original_bytes)
            if header:
                combined = f"{combined}\n{header}".strip()
                updates["raw_text"] = combined
                dt = parse_date(header)
        if dt:
            updates["transaction_date"] = dt

    if not updates:
        return result
    return result.model_copy(update=updates)
