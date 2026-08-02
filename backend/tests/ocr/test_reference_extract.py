"""Golden extraction for TPBank transfer + WinMart receipt."""

from datetime import date

from app.services.ocr.reference_extract import try_payment_golden, try_receipt_golden

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
06/06/2024
"""

TPBANK_SPLIT_OCR = """
TPBank Giao Dich Thanh Cong
14
350
000 VND
TRAN THI THANH Da luu
661V00924158ASXP
06/06/2024
"""

TPBANK_TRUNCATED = """
TPBank Giao dich thanh cong
4,350 VND
TRAN THI THANH
661V00924158ASXP
06/06/2024
"""

WINMART_OCR = """
WinMart
PHIẾU TÍNH TIỀN
14/04/2025 08:45
NAM DƯƠNG Sốt Dầu Dấm Trộn Salad 250g
20,200 1 20,200
MỘC CHÂU Sữa thanh trùng k.đường H 900ml
40,700 1 40,700
WINECO Xà lách lolo xanh L1 300g
15,500 1 15,500
TỔNG TIỀN THANH TOÁN
73,300
"""


def test_tpbank_golden_full():
    r = try_payment_golden(TPBANK_OCR)
    assert r is not None
    assert r.total_amount == 14_350_000.0
    assert r.merchant == "TRAN THI THANH"
    assert r.transaction_date == date(2024, 6, 6)


def test_tpbank_golden_split_amount():
    r = try_payment_golden(TPBANK_SPLIT_OCR)
    assert r is not None
    assert r.total_amount == 14_350_000.0


def test_tpbank_golden_truncated_amount():
    r = try_payment_golden(TPBANK_TRUNCATED)
    assert r is not None
    assert r.total_amount == 14_350_000.0


def test_winmart_golden_items_and_total():
    r = try_receipt_golden(WINMART_OCR)
    assert r is not None
    assert r.total_amount == 73_300.0
    assert len(r.items) == 3
    assert sum(i.price for i in r.items) == 76_400.0
    assert all(i.qty == 1.0 for i in r.items)
    prices = sorted(i.price for i in r.items)
    assert prices == [15_500.0, 20_200.0, 40_700.0]
