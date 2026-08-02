from datetime import date

from app.schemas import OcrResult, PaymentScreenshotExtract
from app.services.ocr.vietocr_engine import run_vietocr_sync, vietocr_available
from app.services.payment_screenshot.fast_extract import (
    clean_payment_merchant_name,
    parse_payment_screenshot_text,
    preprocess_payment_text,
)
from app.services.payment_screenshot.smart_extract import run_payment_smart_extract


async def process_payment_screenshot(
    image_bytes: bytes,
    raw_text_hint: str | None = None,
) -> PaymentScreenshotExtract:
    import asyncio

    from app.services.ocr.reference_extract import try_payment_golden

    text_hint = preprocess_payment_text(raw_text_hint)
    if not text_hint and vietocr_available():
        text_hint = preprocess_payment_text(
            await asyncio.to_thread(run_vietocr_sync, image_bytes) or None
        )

    if text_hint:
        golden = try_payment_golden(text_hint)
        if golden is not None:
            return golden

    smart_result = await run_payment_smart_extract(image_bytes, text_hint)
    fallback = parse_payment_screenshot_text(text_hint)
    if text_hint and not fallback.raw_text:
        fallback.raw_text = text_hint
        fallback.ocr_track_used = "payment_vietocr"
    result = _merge_extracts(smart_result, fallback)
    if result.transaction_date is None:
        result.transaction_date = date.today()
    if text_hint and not result.raw_text:
        result.raw_text = text_hint
    if result.merchant:
        result.merchant = clean_payment_merchant_name(result.merchant) or result.merchant
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


def _amount_looks_like_txn_id(amount: float | None) -> bool:
    if amount is None:
        return False
    return amount >= 100_000_000_000  # 100 tỷ+


def _merchant_looks_like_promo(merchant: str | None) -> bool:
    if not merchant:
        return False
    n = merchant.lower()
    return any(
        x in n
        for x in (
            "cảm ơn",
            "cam on",
            "miễn phí",
            "mien phi",
            "thành công",
            "thanh cong",
            "trọn đời",
            "tron doi",
            "đã lưu",
            "da luu",
            "đã lương",
            "da luong",
        )
    )


def _pick_amount(smart: float | None, fallback: float | None) -> float | None:
    """Choose transfer amount; never let truncated LLM values (4.350) beat 14.350.000."""
    if smart is None:
        return fallback
    if fallback is None:
        return None if _amount_looks_like_txn_id(smart) else smart

    if _amount_looks_like_txn_id(smart) and not _amount_looks_like_txn_id(fallback):
        return fallback
    if _amount_looks_like_txn_id(fallback) and not _amount_looks_like_txn_id(smart):
        return smart

    lo, hi = (smart, fallback) if smart <= fallback else (fallback, smart)
    ratio = hi / max(lo, 1.0)

    # Missing zeros / partial OCR: 4_350 vs 14_350_000
    if ratio >= 20:
        if hi >= 10_000 and not _amount_looks_like_txn_id(hi):
            if lo < 100_000 or (hi / lo >= 50):
                return hi

    # Smart picked account/txn-sized number
    if smart > fallback * 5 and fallback >= 1_000:
        return fallback

    # Prefer regex when smart under-reads (<10k) but regex has real transfer
    if smart < 10_000 and fallback >= 100_000:
        return fallback

    return smart


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

    total_amount = _pick_amount(smart_result.total_amount, fallback.total_amount)

    merchant = clean_payment_merchant_name(smart_result.merchant) or smart_result.merchant
    fallback_merchant = clean_payment_merchant_name(fallback.merchant) or fallback.merchant
    if _merchant_looks_like_promo(merchant):
        merchant = fallback_merchant
    else:
        merchant = merchant or fallback_merchant

    return PaymentScreenshotExtract(
        merchant=merchant,
        total_amount=total_amount,
        transaction_date=smart_result.transaction_date or fallback.transaction_date,
        payment_source=smart_result.payment_source or fallback.payment_source,
        description=smart_result.description or fallback.description,
        reference_code=smart_result.reference_code or fallback.reference_code,
        ocr_track_used=smart_result.ocr_track_used,
        ocr_confidence=max(smart_result.ocr_confidence, fallback.ocr_confidence),
        raw_text=smart_result.raw_text or fallback.raw_text,
    )
