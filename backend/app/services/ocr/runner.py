"""Standalone OCR runner — no DB required (for CLI testing)."""

from typing import Optional

from app.config import settings
from app.schemas import OcrResult
from app.services.ocr.fast_track import _has_local_ocr_engine, run_fast_track
from app.services.ocr.preprocess import preprocess_receipt_image
from app.services.ocr.smart_track import run_smart_track
from app.services.ocr.validate import validate_and_refine
from app.services.ocr.vintern import is_vintern_available


def _vision_ocr_available() -> bool:
    return bool(is_vintern_available() or settings.gemini_api_key or settings.openai_api_key)


async def run_ocr_standalone(
    image_bytes: bytes,
    *,
    raw_text_hint: Optional[str] = None,
    is_low_quality: bool = False,
    skip_preprocess: bool = False,
    force_track: Optional[str] = None,
) -> OcrResult:
    """
    Run OCR pipeline without DB / merchant correction.
    force_track: fast | smart | vintern | gemini | openai | local
    """
    processed = image_bytes if skip_preprocess else preprocess_receipt_image(image_bytes)

    if force_track == "local":
        from app.services.ocr.local_ocr import run_local_ocr

        text = run_local_ocr(processed)
        return validate_and_refine(await run_fast_track(processed, text))

    if force_track == "fast":
        return validate_and_refine(await run_fast_track(processed, raw_text_hint))

    if force_track == "smart":
        return validate_and_refine(await run_smart_track(processed, raw_text_hint, end_to_end=True))

    if force_track in ("vintern", "gemini", "openai"):
        return validate_and_refine(
            await _run_forced_smart(processed, raw_text_hint, force_track, original_bytes=image_bytes)
        )

    # Default CR-OCR routing (no reference correction)
    fast_result = await run_fast_track(processed, raw_text_hint)
    amount_found = fast_result.total_amount is not None
    date_found = fast_result.transaction_date is not None
    has_text_hint = bool(raw_text_hint or fast_result.raw_text)

    if (
        has_text_hint
        and fast_result.ocr_confidence >= settings.ocr_fast_confidence_threshold
        and amount_found
        and date_found
        and not is_low_quality
    ):
        result = fast_result
    elif not has_text_hint and _vision_ocr_available() and not _has_local_ocr_engine():
        result = await run_smart_track(processed, None, end_to_end=True)
    elif fast_result.ocr_confidence >= settings.ocr_smart_confidence_threshold:
        result = await run_smart_track(processed, fast_result.raw_text or raw_text_hint, end_to_end=False)
    else:
        result = await run_smart_track(processed, None, end_to_end=True)

    return validate_and_refine(result)


async def _run_forced_smart(
    image_bytes: bytes,
    raw_text: Optional[str],
    track: str,
    *,
    original_bytes: Optional[bytes] = None,
) -> OcrResult:
    from app.services.ocr.smart_track import _gemini_extract, _heuristic_smart_fallback, _openai_extract
    from app.services.ocr.vintern import run_vintern

    if track == "vintern":
        result = await run_vintern(image_bytes, raw_text, original_bytes=original_bytes)
        if result:
            return result
        raise RuntimeError(
            "Vintern failed. Check logs above — ensure requirements-ocr.txt is installed "
            "and model can load (GPU/MPS/CPU)."
        )
    if track == "gemini":
        result = await _gemini_extract(image_bytes, raw_text, end_to_end=not raw_text)
        return result or _heuristic_smart_fallback(raw_text, end_to_end=not raw_text)
    if track == "openai":
        result = await _openai_extract(image_bytes, raw_text, end_to_end=not raw_text)
        return result or _heuristic_smart_fallback(raw_text, end_to_end=not raw_text)
    return _heuristic_smart_fallback(raw_text, end_to_end=not raw_text)
