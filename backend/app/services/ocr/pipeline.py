"""Confidence-Routed Hybrid OCR (CR-OCR) pipeline.

Primary path: VietOCR Fast Track. Smart Track (Vintern/Gemini/OpenAI) is optional fallback.
"""

from typing import Optional

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.models import MerchantReference
from app.schemas import OcrResult
from app.services.normalize import normalize_ocr_result
from app.services.ocr.fast_track import _has_local_ocr_engine, run_fast_track
from app.services.ocr.reference_correction import fuzzy_match_merchant
from app.services.ocr.smart_track import run_smart_track


def _vision_ocr_available() -> bool:
    """Cloud/self-host VLM fallback — Qwen-VL is no longer used for OCR."""
    return bool(
        settings.vintern_api_url
        or settings.gemini_api_key
        or settings.openai_api_key
    )


async def process_receipt(
    db: AsyncSession,
    user_id: int,
    image_bytes: bytes,
    is_low_quality: bool = False,
    raw_text_hint: Optional[str] = None,
) -> OcrResult:
    # VietOCR raw text → LLM JSON (inside fast_track). No regex before LLM.
    fast_result = await run_fast_track(image_bytes, raw_text_hint)

    amount_found = fast_result.total_amount is not None
    date_found = fast_result.transaction_date is not None
    avg_conf = fast_result.ocr_confidence
    has_text_hint = bool(raw_text_hint)
    has_local = _has_local_ocr_engine()
    has_raw = bool((fast_result.raw_text or "").strip())

    # Soften low-quality routing: still try local/LLM first; cloud only as backup
    local_ok = (
        has_local
        and avg_conf >= settings.ocr_fast_confidence_threshold
        and amount_found
    )
    hint_ok = (
        has_text_hint
        and avg_conf >= settings.ocr_fast_confidence_threshold
        and amount_found
        and date_found
    )
    llm_structured = fast_result.ocr_track_used == "fast_llm"

    if local_ok or hint_ok or llm_structured:
        result = fast_result
    elif has_raw and avg_conf >= settings.ocr_smart_confidence_threshold:
        if _vision_ocr_available():
            result = await run_smart_track(
                image_bytes, fast_result.raw_text or None, end_to_end=False
            )
        else:
            result = fast_result
    elif _vision_ocr_available() and not has_local:
        result = await run_smart_track(image_bytes, None, end_to_end=True)
    elif _vision_ocr_available() and is_low_quality and not amount_found:
        result = await run_smart_track(
            image_bytes, fast_result.raw_text or None, end_to_end=False
        )
    else:
        result = fast_result
    # Light normalize for LLM JSON (keep LLM names). Heavy keyword rewrite only for regex path.
    result = normalize_ocr_result(result)

    # Optional fuzzy merchant match against user/global references (not receipt regex)
    result = await _apply_reference_correction(db, user_id, result)

    from app.services.metrics.pipeline import record_ocr_track

    await record_ocr_track(db, result.ocr_track_used)

    return result


async def _apply_reference_correction(db: AsyncSession, user_id: int, result: OcrResult) -> OcrResult:
    if not result.merchant:
        return result

    refs_result = await db.execute(
        select(MerchantReference.merchant_name).where(MerchantReference.user_id == user_id)
    )
    references = [r[0] for r in refs_result.all()]

    from app.models import Merchant

    global_result = await db.execute(select(Merchant.name).limit(500))
    references.extend([r[0] for r in global_result.all()])

    corrected = fuzzy_match_merchant(result.merchant, references)
    if corrected:
        result.merchant = corrected

    return result
