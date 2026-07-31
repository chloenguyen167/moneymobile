"""Unit tests for Vietnamese receipt parsing."""

from app.services.ocr.parse_utils import (
    infer_total_from_items_heuristic,
    infer_total_from_receipt_math,
    parse_final_amount,
    parse_vnd_number,
)
from app.services.ocr.validate import validate_and_refine
from app.schemas import OcrResult, ReceiptItem


SHARE_TEA_TEXT = """
Share Tea
PHIẾU THANH TOÁN
29.03.2017 17:08
Trà sữa trân châu nhỏ 43.000
Trà xanh xoài kem sữa 48.000
Sương sáo 8.000
Thành tiền: 99.000
Tiền chiết khấu 30% 29.700
Tiền Thanh Toán 69.300
Tiền mặt VND 69.300
"""


def test_parse_vnd_spaced():
    assert parse_vnd_number("99 000") == 99000.0
    assert parse_vnd_number("69.300") == 69300.0


def test_parse_final_amount_prefers_payment_line():
    assert parse_final_amount(SHARE_TEA_TEXT) == 69300.0


def test_infer_total_from_receipt_math_with_discount():
    assert infer_total_from_receipt_math(SHARE_TEA_TEXT, 99000) == 69300.0


def test_items_heuristic_discount():
    assert infer_total_from_items_heuristic(99000) == 69300.0


def test_validate_raw_payment_hint():
    result = OcrResult(
        merchant="Share Tea",
        items=[
            ReceiptItem(name="Trà sữa trân châu nhỏ", price=43000, qty=1),
            ReceiptItem(name="Trà xanh xoài kem sữa", price=48000, qty=1),
            ReceiptItem(name="Sương sáo", price=8000, qty=1),
        ],
        total_amount=99000,
        transaction_date=None,
        ocr_track_used="vintern",
        ocr_confidence=0.85,
        raw_text="69.300",
    )
    refined = validate_and_refine(result)
    assert refined.total_amount == 69300.0


def test_validate_corrects_from_full_receipt_text():
    result = OcrResult(
        merchant="Share Tea",
        items=[
            ReceiptItem(name="Trà sữa trân châu nhỏ", price=43000, qty=1),
            ReceiptItem(name="Trà xanh xoài kem sữa", price=48000, qty=1),
            ReceiptItem(name="Sương sáo", price=8000, qty=1),
        ],
        total_amount=55000,
        transaction_date=None,
        ocr_track_used="vintern",
        ocr_confidence=0.85,
        raw_text=SHARE_TEA_TEXT,
    )
    refined = validate_and_refine(result)
    assert refined.total_amount == 69300.0
    assert refined.transaction_date is not None
