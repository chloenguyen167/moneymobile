"""Confidence-Routed Hybrid OCR (CR-OCR) pipeline."""

from typing import Optional

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.models import MerchantReference
from app.schemas import OcrResult
from app.services.ocr.fast_track import _has_local_ocr_engine, run_fast_track
from app.services.ocr.preprocess import preprocess_receipt_image
from app.services.ocr.reference_correction import fuzzy_match_merchant
from app.services.ocr.smart_track import run_smart_track
from app.services.ocr.validate import validate_and_refine
from app.services.ocr.vintern import is_vintern_available


def _vision_ocr_available() -> bool:
    return bool(is_vintern_available() or settings.gemini_api_key or settings.openai_api_key)


async def process_receipt(
    db: AsyncSession,
    user_id: int,
    image_bytes: bytes,
    is_low_quality: bool = False,
    raw_text_hint: Optional[str] = None,
) -> OcrResult:
    image_bytes = preprocess_receipt_image(image_bytes)

    # Step 2: Fast Track (local OCR / text hint)
    fast_result = await run_fast_track(image_bytes, raw_text_hint)

    amount_found = fast_result.total_amount is not None
    date_found = fast_result.transaction_date is not None
    avg_conf = fast_result.ocr_confidence
    has_text_hint = bool(raw_text_hint or fast_result.raw_text)

    # Step 3: Routing
    if (
        has_text_hint
        and avg_conf >= settings.ocr_fast_confidence_threshold
        and amount_found
        and date_found
        and not is_low_quality
    ):
        result = fast_result
    elif not has_text_hint and _vision_ocr_available() and not _has_local_ocr_engine():
        # No on-box OCR — always use Vintern/Gemini/OpenAI for image input
        result = await run_smart_track(image_bytes, None, end_to_end=True)
    elif avg_conf >= settings.ocr_smart_confidence_threshold:
        result = await run_smart_track(image_bytes, fast_result.raw_text or None, end_to_end=False)
    else:
        result = await run_smart_track(image_bytes, None, end_to_end=True)

    result = validate_and_refine(result)

    # Step 5: Post-OCR reference correction
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
