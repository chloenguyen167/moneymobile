from datetime import date

from app.schemas import OcrResult, PaymentScreenshotExtract
from app.services.payment_screenshot.fast_extract import parse_payment_screenshot_text
from app.services.payment_screenshot.smart_extract import run_payment_smart_extract


async def process_payment_screenshot(
    image_bytes: bytes,
    raw_text_hint: str | None = None,
) -> PaymentScreenshotExtract:
    smart_result = await run_payment_smart_extract(image_bytes, raw_text_hint)
    fallback = parse_payment_screenshot_text(raw_text_hint)
    result = _merge_extracts(smart_result, fallback)
    if result.transaction_date is None:
        result.transaction_date = date.today()
    return result


def payment_extract_to_ocr_result(extract: PaymentScreenshotExtract) -> OcrResult:
    return OcrResult(
        merchant=extract.merchant or extract.payment_source,
        items=[],
        total_amount=extract.total_amount,
        transaction_date=extract.transaction_date,
        ocr_track_used=extract.ocr_track_used,
        ocr_confidence=extract.ocr_confidence,
        raw_text=extract.raw_text or extract.description,
    )


def _merge_extracts(
    smart_result: PaymentScreenshotExtract | None,
    fallback: PaymentScreenshotExtract,
) -> PaymentScreenshotExtract:
    if smart_result is None:
        return fallback

    has_smart_signal = any(
        [
            smart_result.merchant,
            smart_result.total_amount,
            smart_result.payment_source,
            smart_result.description,
            smart_result.reference_code,
            smart_result.transaction_date,
        ]
    )
    if not has_smart_signal:
        return fallback

    return PaymentScreenshotExtract(
        merchant=smart_result.merchant or fallback.merchant,
        total_amount=smart_result.total_amount or fallback.total_amount,
        transaction_date=smart_result.transaction_date or fallback.transaction_date,
        payment_source=smart_result.payment_source or fallback.payment_source,
        description=smart_result.description or fallback.description,
        reference_code=smart_result.reference_code or fallback.reference_code,
        ocr_track_used=smart_result.ocr_track_used,
        ocr_confidence=max(smart_result.ocr_confidence, fallback.ocr_confidence),
        raw_text=smart_result.raw_text or fallback.raw_text,
    )
