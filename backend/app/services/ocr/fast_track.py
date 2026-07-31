"""Fast Track OCR — regex/heuristic extraction on local OCR or text hint."""

from typing import Optional

from app.schemas import OcrResult
from app.services.ocr.local_ocr import is_local_ocr_available, run_local_ocr
from app.services.ocr.parse_utils import (
    estimate_text_confidence,
    parse_amount,
    parse_date,
    parse_items,
    parse_merchant,
)


def _has_local_ocr_engine() -> bool:
    return is_local_ocr_available()


async def run_fast_track(image_bytes: bytes, raw_text_hint: Optional[str] = None) -> OcrResult:
    """
    Extract from OCR text hint or local EasyOCR output.
    Without text/engine, returns low confidence so CR-OCR routes to smart track.
    """
    if raw_text_hint:
        text = raw_text_hint
    elif _has_local_ocr_engine():
        text = run_local_ocr(image_bytes)
    else:
        return OcrResult(
            merchant=None,
            items=[],
            total_amount=None,
            transaction_date=None,
            ocr_track_used="fast",
            ocr_confidence=0.0,
            raw_text="",
        )

    amount = parse_amount(text)
    dt = parse_date(text)
    merchant = parse_merchant(text)
    items = parse_items(text)
    confidence = estimate_text_confidence(text, amount, dt)

    return OcrResult(
        merchant=merchant,
        items=items,
        total_amount=amount,
        transaction_date=dt,
        ocr_track_used="fast",
        ocr_confidence=confidence,
        raw_text=text,
    )
