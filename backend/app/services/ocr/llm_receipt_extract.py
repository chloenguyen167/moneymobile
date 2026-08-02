"""LLM structuring of Vietnamese receipt OCR text → OcrResult.

Contract:
  - Input = RAW text from VietOCR (or client hint). Never pre-parsed by regex.
  - Output = structured JSON (merchant, date, total, items).
  - Qwen-VL is not used; image reading is VietOCR only.
"""

from __future__ import annotations

import logging
from datetime import date
from typing import Optional

from app.config import settings
from app.schemas import OcrResult, ReceiptItem
from app.services.llm.ollama_client import chat_json, ollama_available
from app.services.ocr.receipt_parse import (
    is_junk_item_name,
    parse_receipt_date,
    parse_receipt_items,
    parse_receipt_merchant,
    parse_receipt_total,
)

logger = logging.getLogger(__name__)

STRUCT_SCHEMA = """
Trả JSON đúng schema (không markdown):
{
  "merchant": string|null,
  "transaction_date": "YYYY-MM-DD"|null,
  "total_amount": number|null,
  "confidence": number,
  "items": [{"name": string, "price": number, "qty": number, "unit_price": number|null}]
}
"""

TEXT_STRUCT_PROMPT = """Bạn là chuyên gia đọc hóa đơn Việt Nam / Starbucks / siêu thị.
Input là TEXT thô từ OCR (có thể sai chính tả, thiếu dấu, lệch cột, tên và số nằm 2 dòng).
Hãy trả JSON cấu trúc đầy đủ — LIỆT KÊ TẤT CẢ mặt hàng, không được bỏ sót.

Nguyên tắc BẮT BUỘC:
1. items = mọi sản phẩm khách mua. Hóa đơn 8 món → items phải có ~8 phần tử.
   Layout phổ biến: dòng tên món, dòng tiếp theo là SL / đơn giá / thành tiền.
2. price = thành tiền dòng (T.Tiền / Amount), KHÔNG phải đơn giá nếu có cột thành tiền riêng.
3. qty có thể là số thập phân (kg): 0.87, 0.116 — giữ nguyên, KHÔNG làm tròn thành 1.
4. total_amount = số khách PHẢI TRẢ (Total / Tổng tiền / Thành tiền / Phải trả).
   KHÔNG lấy: Cash / Tiền mặt / Tiền đưa / Change / Tiền thừa / Tiền cà thẻ (nếu khác tổng).
   Ví dụ Starbucks: Total 88,000 + Cash 500,000 + Change 412,000 → total_amount = 88000.
5. Bỏ khỏi items: Cash, Change, Subtotal, Total tax, Tổng tiền, cảm ơn, địa chỉ, SĐT, NV, barcode.
6. merchant = tên cửa hàng ngắn (Bách Hóa Xanh, Starbucks, …).
7. Sửa tên món nếu OCR lệch nhẹ khi ngữ cảnh rõ (CAFFE MOCHA, Đùi tỏi gà, …).

{schema}

TEXT OCR THÔ:
---
{ocr_text}
---
"""


def llm_struct_enabled() -> bool:
    return bool(settings.ocr_llm_struct_enabled and ollama_available())


async def structure_receipt_text(ocr_text: str) -> Optional[OcrResult]:
    """Pass raw OCR text to LLM → structured OcrResult, merged with regex fallback."""
    text = (ocr_text or "").strip()
    if not text or not llm_struct_enabled():
        return None

    clipped = text if len(text) <= 8000 else text[:8000]
    prompt = TEXT_STRUCT_PROMPT.format(schema=STRUCT_SCHEMA, ocr_text=clipped)
    data = await chat_json(prompt, num_predict=4096)
    llm_result: OcrResult | None = None
    if data:
        llm_result = _dict_to_ocr_result(data, raw_text=text, track="fast_llm")

    regex_result = _regex_structure(text)
    merged = _merge_llm_and_regex(llm_result, regex_result, text)
    if merged is None:
        return None
    _apply_confidence(merged)
    logger.info(
        "Structured receipt: merchant=%s total=%s items=%d conf=%.2f track=%s",
        merged.merchant,
        merged.total_amount,
        len(merged.items),
        merged.ocr_confidence,
        merged.ocr_track_used,
    )
    return merged


def _regex_structure(text: str) -> OcrResult:
    amount = parse_receipt_total(text)
    dt = parse_receipt_date(text)
    merchant = parse_receipt_merchant(text)
    items = parse_receipt_items(text)
    return OcrResult(
        merchant=merchant,
        items=items,
        total_amount=amount,
        transaction_date=dt,
        ocr_track_used="fast",
        ocr_confidence=0.7,
        raw_text=text,
    )


def _items_sum(items: list[ReceiptItem]) -> float:
    return float(sum(i.price for i in items))


def _score_items_vs_total(items: list[ReceiptItem], total: float | None) -> float:
    if not items:
        return -1.0
    if not total or total <= 0:
        return float(len(items))
    ratio = _items_sum(items) / total
    if 0.9 <= ratio <= 1.08:
        return 100.0 + len(items)
    if 0.8 <= ratio <= 1.2:
        return 50.0 + len(items)
    return float(len(items)) - abs(1.0 - ratio) * 10


def _merge_llm_and_regex(
    llm: OcrResult | None,
    regex: OcrResult,
    raw_text: str,
) -> OcrResult | None:
    if llm is None and not regex.items and regex.total_amount is None and not regex.merchant:
        return None
    if llm is None:
        return regex

    # --- total: never prefer cash-like LLM total when regex has labeled Total ---
    total = llm.total_amount
    if regex.total_amount and regex.total_amount > 0:
        if total is None:
            total = regex.total_amount
        elif total > regex.total_amount * 1.35:
            # LLM likely picked Cash (500k) over Total (88k)
            logger.info(
                "Prefer regex total %s over LLM total %s (cash-like)",
                regex.total_amount,
                total,
            )
            total = regex.total_amount

    # --- items: prefer the set that matches total better / has more real products ---
    llm_items = [i for i in llm.items if not is_junk_item_name(i.name)]
    regex_items = [i for i in regex.items if not is_junk_item_name(i.name)]

    # Single LLM item priced ≈ total while regex found many → use regex
    if (
        len(llm_items) <= 1
        and len(regex_items) >= 2
        and total
        and llm_items
        and abs(llm_items[0].price - total) / total < 0.05
    ):
        items = regex_items
        track = "fast_llm+regex_items"
    elif _score_items_vs_total(regex_items, total) > _score_items_vs_total(llm_items, total) + 1:
        items = regex_items
        track = "fast_llm+regex_items"
    elif len(regex_items) > len(llm_items) + 1:
        items = regex_items
        track = "fast_llm+regex_items"
    else:
        items = llm_items or regex_items
        track = "fast_llm"

    # If still one item with price == total but regex empty, keep but don't invent
    if total and items and len(items) == 1 and abs(items[0].price - total) / max(total, 1) < 0.02:
        # OK for single-item cafe receipt
        pass

    # If items sum is solid and total missing / wrong, trust items sum
    if items:
        s = _items_sum(items)
        if total is None and s > 0:
            total = s
        elif total and s > 0 and abs(s - total) / total > 0.25 and 0.9 <= s / total <= 1.1:
            pass
        elif total and s > 0 and abs(s - total) / total <= 0.08:
            pass
        elif (
            total
            and s > 0
            and abs(s - total) / total > 0.2
            and regex.total_amount
            and abs(s - regex.total_amount) / regex.total_amount <= 0.08
        ):
            total = regex.total_amount

    merchant = llm.merchant or regex.merchant
    tx_date = llm.transaction_date or regex.transaction_date

    return OcrResult(
        merchant=merchant,
        items=items,
        total_amount=total,
        transaction_date=tx_date,
        ocr_track_used=track,
        ocr_confidence=llm.ocr_confidence or 0.8,
        raw_text=raw_text,
    )


def _apply_confidence(result: OcrResult) -> None:
    conf = result.ocr_confidence
    if result.items and result.total_amount and result.total_amount > 0:
        items_sum = sum(i.price for i in result.items)
        ratio = items_sum / result.total_amount
        if 0.85 <= ratio <= 1.15:
            conf = max(conf, 0.9)
        elif 1.0 <= ratio <= 1.25:
            conf = max(conf, 0.85)
        elif ratio > 1.4 or ratio < 0.6:
            conf = min(conf, 0.55)
    if result.merchant and result.transaction_date and result.items:
        conf = max(conf, 0.75)
    result.ocr_confidence = max(0.0, min(conf, 0.98))


def _dict_to_ocr_result(data: dict, raw_text: str, track: str) -> Optional[OcrResult]:
    items: list[ReceiptItem] = []
    for raw in data.get("items") or []:
        if not isinstance(raw, dict):
            continue
        name = str(raw.get("name") or "").strip()
        if not name or "price" not in raw:
            continue
        if is_junk_item_name(name):
            continue
        try:
            price = float(raw["price"])
            qty_raw = raw.get("qty", 1)
            qty = float(qty_raw) if qty_raw is not None else 1.0
            if qty <= 0 or qty > 500:
                qty = 1.0
            unit_raw = raw.get("unit_price")
            unit_price = float(unit_raw) if unit_raw is not None else None
        except (TypeError, ValueError):
            continue
        if price < 100 or price > 50_000_000:
            continue
        # Infer qty from unit_price without forcing integers (keep kg decimals)
        if unit_price and unit_price > 0 and price > 0:
            inferred = price / unit_price
            if 0.01 <= inferred <= 500 and abs(inferred - qty) > 0.15:
                qty = round(inferred, 3)
        items.append(
            ReceiptItem(name=name[:120], price=price, qty=qty, unit_price=unit_price)
        )

    tx_date = None
    if data.get("transaction_date"):
        try:
            tx_date = date.fromisoformat(str(data["transaction_date"])[:10])
        except ValueError:
            pass

    total = data.get("total_amount")
    try:
        total_amount = float(total) if total is not None else None
    except (TypeError, ValueError):
        total_amount = None

    merchant = data.get("merchant")
    if merchant is not None:
        merchant = str(merchant).strip()[:80] or None

    if not items and total_amount is None and not merchant and tx_date is None:
        return None

    conf = data.get("confidence")
    try:
        confidence = float(conf) if conf is not None else 0.8
    except (TypeError, ValueError):
        confidence = 0.8

    return OcrResult(
        merchant=merchant,
        items=items,
        total_amount=total_amount,
        transaction_date=tx_date,
        ocr_track_used=track,
        ocr_confidence=max(0.0, min(confidence, 0.98)),
        raw_text=raw_text,
    )
