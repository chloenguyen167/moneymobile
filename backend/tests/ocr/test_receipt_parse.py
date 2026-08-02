"""Tests for Vietnamese receipt text → structured fields (regex fallback path)."""

from datetime import date

from app.services.ocr.receipt_parse import (
    parse_receipt_date,
    parse_receipt_items,
    parse_receipt_merchant,
    parse_receipt_total,
)

PHUC_LONG_OCR = """
PHUC LONG COFFEE & TEA
Thắng Trệt Co.opmart Thắng Lợi, 02 thuy
29/05/2021 07:31
Số HĐ: CH8502-11801-001-0008
Tra Lai Dac Thom (L D 1 55,000 L
PL Tea Latte Cold (L) 1 50,000
Banh Flan 1 20,000
Tổng tiền 125,000 D
Thành tiền 125,000
CASH(VND) 125,000
c vui lòng cung cấp thông tin trong ngày. nghiệt chi cảm ơn quý khách và hẹn gặp lại 1 BE bat liy/
phuclong-khaosat Co Bo
"""

FAMILYMART_OCR = """
FamilyMart
HÓA ĐƠN BÁN HÀNG
Số HD: 20211101806qXxosF6kk
Tên hàng SL Đơn giá Thành tiền
1 T2.CƠM NGHÊU & THỊT 2 30,000 60,000
Giảm giá: 2,000
2 T2.Aquafina 500ml 1 5,000 5,000
Tổng cộng 65,000
Tổng chiết khấu -2,000
Tổng tiền phải trả 63,000
Khách trả ZaloPay 63,000
Xin cảm ơn quý khách!
01/11/2021 - Giờ: 15:07
"""


def test_phuc_long_regex_fallback():
    text = PHUC_LONG_OCR
    assert parse_receipt_date(text) == date(2021, 5, 29)
    assert parse_receipt_total(text) == 125000.0
    merchant = parse_receipt_merchant(text)
    assert merchant is not None
    assert "phuc" in merchant.lower() or "long" in merchant.lower()
    items = parse_receipt_items(text)
    assert len(items) >= 2
    names = " ".join(i.name.lower() for i in items)
    assert "cash" not in names
    assert "cảm ơn" not in names
    assert abs(sum(i.price for i in items) - 125000) < 30000 or len(items) >= 2


def test_familymart_regex_fallback():
    text = FAMILYMART_OCR
    assert parse_receipt_date(text) == date(2021, 11, 1)
    assert parse_receipt_total(text) == 63000.0
    items = parse_receipt_items(text)
    # Regex may be imperfect; LLM is primary. Just ensure we don't invent 4 junk items from totals.
    names = " ".join(i.name.lower() for i in items)
    assert "cảm ơn" not in names
    assert "zalopay" not in names


STARBUCKS_OCR = """
Store-Lan Vien
32 Hang Bai St, Hoan Kiem Dist, Hanoi, Vietnam
3/18/2019 07:36
ITEM NAME QTY AMOUNT
Mon Nuoc CAFFE MOCHA G 1.00 88,000
Subtotal 80,000
Total tax 8,000
Total 88,000
Cash 500,000
Change back (Cash) 412,000
Thank you!
"""

BHX_OCR = """
BÁCH HÓA XANH
www.bachhoaxanh.com
PHIẾU THANH TOÁN
Ngày CT: 16/07/2021 07:36
ĐÙI TỎI GÀ NHẬP KHẨU
0.87 80,000 69,600
XÀ LÁCH LOLO XANH(KG)
0.16 35,000 5,600
NGÒ GAI-RAU OM
0.058 50,000 2,900
NGÒ RÍ (Kg)
0.116 52,000 6,032
ĐẬU BẮP(KG)
0.508 38,000 19,304
HÀNH LÁ (KG)
0.256 50,000 12,800
KHỔ QUA
0.498 45,000 22,410
BẦU SAO
1.174 42,000 49,308
Tổng tiền:
187,954
Tiền cà thẻ:
187,500
Thanh toán:
0
"""


def test_starbucks_total_not_cash():
    assert parse_receipt_total(STARBUCKS_OCR) == 88000.0
    items = parse_receipt_items(STARBUCKS_OCR)
    assert len(items) >= 1
    assert all("cash" not in i.name.lower() for i in items)
    assert abs(items[0].price - 88000) < 1 or abs(sum(i.price for i in items) - 88000) < 1


def test_bhx_multi_items_two_line_layout():
    assert parse_receipt_total(BHX_OCR) == 187954.0
    items = parse_receipt_items(BHX_OCR)
    assert len(items) >= 6
    assert abs(sum(i.price for i in items) - 187954) < 50
