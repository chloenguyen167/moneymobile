"""Detect whether OCR text is a retail receipt or a payment/bank screenshot."""

from __future__ import annotations

import logging
import re
from typing import Literal

from app.services.llm.ollama_client import chat_json, ollama_available
from app.services.ocr.reference_correction import normalize_vietnamese

logger = logging.getLogger(__name__)

ImageKind = Literal["receipt", "payment_screenshot"]

_PAYMENT_KEYWORDS = [
    "chuyen khoan",
    "chuyen tien",
    "giao dich thanh cong",
    "thanh cong",
    "so du",
    "so tai khoan",
    "stk",
    "nguoi nhan",
    "nguoi chuyen",
    "noi dung",
    "ma gd",
    "ma giao dich",
    "ref",
    "reference",
    "tpbank",
    "vietcombank",
    "techcombank",
    "bidv",
    "mb bank",
    "mbbank",
    "agribank",
    "vpbank",
    "acb",
    "momo",
    "zalopay",
    "shopeepay",
    "viettelpay",
    "vnpay",
    "napas",
    "qr pay",
    "bien dong so du",
    "da nhan",
    "nhan tien",
    "chuyen den",
]

_RECEIPT_KEYWORDS = [
    "hoa don",
    "receipt",
    "tong cong",
    "tong tien",
    "thanh tien",
    "thanh toan",
    "phai tra",
    "don gia",
    "so luong",
    "sl",
    "vat",
    "thue",
    "cam on",
    "thu ngan",
    "sieu thi",
    "cua hang",
    "ban hang",
    "khach hang",
    "dvt",
    "tien mat",
    "cash",
    "bill",
]


def _score_text(text: str) -> tuple[int, int]:
    norm = normalize_vietnamese(text.lower())
    # collapse whitespace
    norm = re.sub(r"\s+", " ", norm)
    pay = sum(1 for kw in _PAYMENT_KEYWORDS if kw in norm)
    receipt = sum(1 for kw in _RECEIPT_KEYWORDS if kw in norm)

    # Structural hints
    lines = [ln.strip() for ln in text.splitlines() if ln.strip()]
    if len(lines) >= 8:
        receipt += 1
    # Many short amount-like lines → receipt
    money_lines = sum(1 for ln in lines if re.search(r"\d{1,3}([.,]\d{3})+", ln))
    if money_lines >= 3:
        receipt += 2
    if money_lines <= 1 and pay >= 1:
        pay += 1
    return pay, receipt


async def detect_document_kind(raw_text: str | None) -> ImageKind:
    """Rule-first classification; LLM only when scores are close."""
    text = (raw_text or "").strip()
    if not text:
        return "receipt"

    pay, receipt = _score_text(text)
    logger.info("Document kind scores: payment=%s receipt=%s", pay, receipt)

    if pay >= receipt + 2:
        return "payment_screenshot"
    if receipt >= pay + 2:
        return "receipt"

    # Ambiguous → LLM
    if ollama_available():
        kind = await _llm_detect(text)
        if kind:
            return kind

    # Tie-break: prefer payment if any strong bank signal else receipt
    return "payment_screenshot" if pay > receipt else "receipt"


async def _llm_detect(text: str) -> ImageKind | None:
    clipped = text if len(text) <= 2500 else text[:2500]
    prompt = f"""Phân loại ảnh dựa trên TEXT OCR thô.
Trả JSON duy nhất: {{"kind": "receipt" | "payment_screenshot", "confidence": 0-1}}

- receipt: hóa đơn mua hàng (siêu thị, quán ăn, nhiều dòng sản phẩm, tổng tiền)
- payment_screenshot: ảnh màn hình chuyển khoản / ví / ngân hàng (1 khoản, người nhận, mã GD, số dư)

TEXT:
---
{clipped}
---
"""
    data = await chat_json(prompt)
    if not data:
        return None
    kind = (data.get("kind") or "").strip()
    if kind in ("receipt", "payment_screenshot"):
        logger.info("LLM document kind=%s conf=%s", kind, data.get("confidence"))
        return kind  # type: ignore[return-value]
    return None
