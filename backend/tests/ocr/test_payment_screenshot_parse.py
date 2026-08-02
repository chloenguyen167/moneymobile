"""Payment screenshot amount / payee extraction (TPBank etc.)."""

from datetime import date

from app.schemas import PaymentScreenshotExtract
from app.services.payment_screenshot.fast_extract import (
    clean_payment_merchant_name,
    parse_payment_screenshot_text,
)
from app.services.payment_screenshot.pipeline import _merge_extracts, _pick_amount

TPBANK_OCR = """
TPBank
Cảm ơn Bạn đã cùng TPBank chuyển khoản miễn phí trọn đời
Giao Dich Thành Công!
14,350,000 VND
PHAM THI TINH
3569 9168 888
TRAN THI THANH
0975 8346 34 | SHB
Đã lưu
Mã giao dịch
661V00924158ASXP
Nội dung
Mai Van Thanh
Thời gian
21:04:23, Ngày 06/06/2024
Cách thức
Chuyển nhanh Napas 247
"""

TPBANK_OCR_NOISY = """
TPBank Cam on chuyen khoan mien phi
Giao Dich Thanh Cong
14.350.000 VND
PHAM THI TINH 35699168888
TRAN THI THANH ĐÃ LƯƠNG 0975834634 SHB
Ma giao dich 66100924158ASXP
Noi dung Mai Van Thanh
06/06/2024
"""

TPBANK_OCR_BADGE = """
14,350,000 VND
TRAN THI THANH Đã lưu
0975 8346 34 | SHB
"""


def test_tpbank_amount_not_txn_id():
    r = parse_payment_screenshot_text(TPBANK_OCR)
    assert r.total_amount == 14_350_000.0
    assert r.transaction_date == date(2024, 6, 6)
    assert r.payment_source == "TPBank"
    assert r.reference_code and "661" in r.reference_code
    assert r.merchant is not None
    assert "TRAN THI THANH" in r.merchant.upper()
    assert "cảm ơn" not in r.merchant.lower() and "cam on" not in r.merchant.lower()
    assert "LUU" not in r.merchant.upper().replace(" ", "")
    assert "LƯU" not in r.merchant.upper()
    assert r.description and "Mai Van Thanh" in r.description


def test_tpbank_noisy_ocr_drops_letter_in_ref():
    r = parse_payment_screenshot_text(TPBANK_OCR_NOISY)
    assert r.total_amount == 14_350_000.0
    assert r.merchant and "THANH" in r.merchant.upper()
    assert "LƯƠNG" not in r.merchant.upper() and "LUONG" not in r.merchant.upper()


def test_strip_da_luu_badge_from_merchant():
    r = parse_payment_screenshot_text(TPBANK_OCR_BADGE)
    assert r.merchant == "TRAN THI THANH"
    assert clean_payment_merchant_name("TRAN THI THANH ĐÃ LƯƠNG") == "TRAN THI THANH"


def test_merge_prefers_regex_over_txn_id_smart_amount():
    smart = PaymentScreenshotExtract(
        merchant="Cảm ơn Bạn đã cùng TPBANK CHUYỂN KHOẢN NA",
        total_amount=661_100_924_158.0,
        transaction_date=date(2024, 6, 6),
        payment_source="TPBank",
        description=None,
        reference_code="661V00924158ASXP",
        ocr_track_used="payment_gemini",
        ocr_confidence=0.9,
    )
    fallback = parse_payment_screenshot_text(TPBANK_OCR)
    merged = _merge_extracts(smart, fallback)
    assert merged.total_amount == 14_350_000.0
    assert merged.merchant and "TRAN" in merged.merchant.upper()


def test_merge_prefers_regex_over_truncated_smart_amount():
    """Regression: LLM returned 4350 while OCR text has 14,350,000 VND."""
    smart = PaymentScreenshotExtract(
        merchant="TRAN THI THANH ĐÃ LƯƠNG",
        total_amount=4_350.0,
        transaction_date=date(2024, 6, 6),
        payment_source="TPBank",
        ocr_track_used="payment_gemini",
        ocr_confidence=0.9,
    )
    fallback = parse_payment_screenshot_text(TPBANK_OCR)
    merged = _merge_extracts(smart, fallback)
    assert merged.total_amount == 14_350_000.0
    assert merged.merchant == "TRAN THI THANH"


def test_pick_amount_truncated_vs_full():
    assert _pick_amount(4_350.0, 14_350_000.0) == 14_350_000.0
    assert _pick_amount(14_350_000.0, 4_350.0) == 14_350_000.0
