"""Post-OCR validation, amount reconciliation, confidence refinement."""

import re

from app.schemas import OcrResult, ReceiptItem
from app.services.ocr.items_parser import items_line_sum, parse_table_items
from app.services.ocr.parse_utils import (
    clean_merchant,
    infer_total_from_receipt_math,
    infer_total_from_items_heuristic,
    parse_date,
    parse_final_amount,
    parse_rounded_payment,
    parse_subtotal_amount,
    parse_total_from_embedded_json,
    parse_vnd_number,
    MAX_RECEIPT_AMOUNT,
)


def _is_plausible_receipt_total(value: float) -> bool:
    return 1_000 <= value <= 5_000_000


def _item_line_total(item: ReceiptItem) -> float:
    if item.line_total is not None:
        return item.line_total
    return item.price * item.qty


def _items_total(items: list[ReceiptItem]) -> float:
    return sum(_item_line_total(item) for item in items)


def _normalize_amount(value) -> float | None:
    if value is None:
        return None
    if isinstance(value, (int, float)):
        v = float(value)
        if v <= 0 or v > MAX_RECEIPT_AMOUNT:
            return None
        return v
    if isinstance(value, str):
        return parse_vnd_number(value)
    return None


def _amounts_from_raw(raw_text: str) -> list[float]:
    amounts: list[float] = []
    for match in re.finditer(r"[\d][\d\s.,]{2,}", raw_text):
        value = parse_vnd_number(match.group())
        if value and 100 <= value <= MAX_RECEIPT_AMOUNT:
            amounts.append(value)
    return amounts


def _parse_date_from_json(raw_text: str):
    from datetime import date

    for pattern in (
        r'"transaction_date"\s*:\s*"(\d{4}-\d{2}-\d{2})"',
        r'"TransactionDate"\s*:\s*"(\d{4}-\d{2}-\d{2})"',
        r'"transaction_date"\s*:\s*"(\d{4}-\d{2}-\d{2})"',
    ):
        match = re.search(pattern, raw_text, re.I)
        if match:
            try:
                return date.fromisoformat(match.group(1))
            except ValueError:
                pass
    return None


# Prompt-example products Vintern tends to hallucinate when not on receipt
_PROMPT_EXAMPLE_MARKERS = (
    "mắm tôm",
    "xốt mè rang",
    "táo royal gala",
    "lê gia",
    "kewpie",
)


def _model_items_hallucinated(model_items: list[ReceiptItem], raw_text: str) -> bool:
    """Detect when VLM copied prompt examples instead of reading the receipt."""
    if not model_items or not raw_text:
        return False
    names = " ".join(i.name.lower() for i in model_items)
    hits = sum(1 for m in _PROMPT_EXAMPLE_MARKERS if m in names)
    if hits < 1:
        return False
    raw_lower = raw_text.lower()
    meat_on_receipt = bool(
        re.search(r"meat|deli|wmnk|thịt|heo|weat\s|cam\s+vàng|ba\s*rọi", raw_lower, re.I)
    )
    examples_in_raw = sum(1 for m in _PROMPT_EXAMPLE_MARKERS if m in raw_lower)
    if hits >= 2:
        return meat_on_receipt or examples_in_raw < hits
    return meat_on_receipt and examples_in_raw == 0


def _model_items_suspicious(items: list[ReceiptItem]) -> bool:
    if len(items) < 2:
        return False
    lines = [round(i.line_total or i.price * i.qty) for i in items]
    if len(set(lines)) == 1:
        return True
    qtys = [round(i.qty, 3) for i in items]
    if len(set(qtys)) == 1 and qtys[0] < 2:
        return True
    return False


def _parsed_items_suspicious(items: list[ReceiptItem]) -> bool:
    if not items:
        return True
    for item in items:
        if item.qty > 10 or item.qty <= 0:
            return True
        if item.price < 1000:
            return True
        if (item.line_total or 0) < 1000:
            return True
    return False


def _items_from_embedded_json(raw_text: str) -> list[ReceiptItem]:
    """Recover items from JSON embedded in VLM raw output."""
    from app.services.ocr.vintern import _parse_json_response, _sanitize_items
    from app.services.ocr.items_parser import parse_item_dict

    data = _parse_json_response(raw_text)
    raw_items = data.get("items") or []
    items = []
    for i in raw_items:
        if isinstance(i, dict):
            parsed = parse_item_dict(i)
            if parsed:
                items.append(parsed)
    return _sanitize_items(items)


def _refine_items(model_items: list[ReceiptItem], raw_text: str) -> list[ReceiptItem]:
    """Re-parse items from raw OCR text when model items are incomplete."""
    if _model_items_hallucinated(model_items, raw_text):
        model_items = []

    embedded = _items_from_embedded_json(raw_text)
    if embedded and (not model_items or len(embedded) >= len(model_items)):
        model_items = embedded

    parsed = parse_table_items(raw_text)
    if _parsed_items_suspicious(parsed):
        parsed = []

    if not parsed:
        return model_items

    model_sum = _items_total(model_items) if model_items else 0
    parsed_sum = items_line_sum(parsed)

    model_broken = (
        not model_items
        or _model_items_hallucinated(model_items, raw_text)
        or _model_items_suspicious(model_items)
        or any(i.qty == 0 for i in model_items)
        or (model_sum > 0 and parsed_sum > model_sum * 1.05)
        or len(parsed) > len(model_items)
    )

    if model_broken and parsed:
        # Prefer parsed when model qty broken; keep model names if longer
        if model_items and len(model_items) == len(parsed):
            merged = []
            for mi, pi in zip(model_items, parsed):
                name = mi.name if len(mi.name) > len(pi.name) else pi.name
                merged.append(
                    ReceiptItem(
                        name=name,
                        price=pi.price,
                        qty=pi.qty,
                        line_total=pi.line_total,
                    )
                )
            return merged
        return parsed

    return model_items if model_items else parsed


def _reconcile_total(
    model_total: float | None,
    items_sum: float,
    raw_text: str | None,
) -> tuple[float | None, str]:
    text_total = parse_final_amount(raw_text) if raw_text else None
    rounded_payment = parse_rounded_payment(raw_text) if raw_text else None
    json_total = parse_total_from_embedded_json(raw_text) if raw_text else None
    math_total = infer_total_from_receipt_math(raw_text, items_sum) if raw_text and items_sum > 0 else None
    subtotal = parse_subtotal_amount(raw_text) if raw_text else None
    raw_amounts = _amounts_from_raw(raw_text) if raw_text else []
    heuristic_total = None

    if items_sum > 0:
        if model_total is None or model_total < items_sum * 0.85 or abs(model_total - items_sum) < items_sum * 0.02:
            heuristic_total = infer_total_from_items_heuristic(items_sum)

    candidates: list[tuple[int, float, str]] = []

    if text_total:
        candidates.append((100, text_total, "text_final"))
    if rounded_payment:
        candidates.append((102, rounded_payment, "rounded_payment"))
    if items_sum > 0 and items_sum >= 5000:
        candidates.append((101, items_sum, "items_sum"))
    if json_total:
        candidates.append((98, json_total, "json_embedded"))
    if math_total:
        candidates.append((95, math_total, "receipt_math"))

    for amount in raw_amounts:
        if items_sum > 0 and amount < items_sum * 0.98 and amount >= items_sum * 0.7:
            candidates.append((97, amount, "raw_payment_hint"))
        elif subtotal and amount < subtotal and amount >= subtotal * 0.9:
            candidates.append((96, amount, "rounded_payment"))

    if heuristic_total:
        candidates.append((70, heuristic_total, "items_heuristic"))

    # Model total only if plausible
    if model_total and model_total <= MAX_RECEIPT_AMOUNT:
        if _is_plausible_receipt_total(model_total):
            if not (items_sum > 0 and abs(model_total - items_sum) < items_sum * 0.02 and text_total):
                candidates.append((80, model_total, "model"))

    # Drop model when clearly wrong (receipt ID, first item price)
    if model_total and items_sum > 0:
        if model_total > items_sum * 1.5 or model_total < items_sum * 0.3:
            candidates = [c for c in candidates if c[2] != "model"]
        if abs(model_total - items_sum) < items_sum * 0.02 and (text_total or json_total):
            candidates = [c for c in candidates if c[2] != "model"]

    if not candidates:
        if items_sum > 0:
            return items_sum, "items_sum"
        return None, "none"

    if model_total and items_sum > 0 and items_sum > model_total * 1.15 and (text_total or math_total):
        candidates = [c for c in candidates if c[2] != "model"]

    candidates.sort(key=lambda x: -x[0])

    if text_total and math_total and abs(text_total - math_total) <= max(text_total * 0.02, 1000):
        return text_total, "text_math_agree"

    return candidates[0][1], candidates[0][2]


def validate_and_refine(result: OcrResult) -> OcrResult:
    """Normalize fields, reconcile items/totals, clean merchant, adjust confidence."""
    raw_text = result.raw_text or ""
    items = _refine_items(result.items or [], raw_text)
    items_sum = _items_total(items) if items else 0.0
    model_total = _normalize_amount(result.total_amount)

    total, total_source = _reconcile_total(model_total, items_sum, raw_text or None)
    if total is None and items_sum > 0:
        total = items_sum
        total_source = "items_sum_fallback"

    merchant = clean_merchant(result.merchant)
    tx_date = (
        result.transaction_date
        or _parse_date_from_json(raw_text)
        or (parse_date(raw_text) if raw_text else None)
    )

    confidence = result.ocr_confidence
    bonuses = 0.0
    penalties = 0.0

    if total is None:
        penalties += 0.15
    if tx_date is None:
        penalties += 0.08
    if not merchant:
        penalties += 0.05

    if total_source in ("text_final", "text_math_agree", "receipt_math", "raw_payment_hint", "json_embedded", "rounded_payment", "items_sum"):
        bonuses += 0.1
    elif total_source == "model" and model_total != total:
        penalties += 0.08

    if total and items_sum > 0:
        ratio = abs(total - items_sum) / max(total, items_sum, 1)
        if ratio <= 0.02:
            bonuses += 0.08
        elif ratio <= 0.15:
            if total < items_sum:
                bonuses += 0.04
        elif ratio > 0.35:
            penalties += 0.1

    if merchant and total and tx_date:
        bonuses += 0.05
    if items and all(i.qty > 0 for i in items):
        bonuses += 0.04
    if items and any(i.line_total for i in items):
        bonuses += 0.03

    # Fill missing line_total from qty × price
    enriched_items = []
    for item in items:
        if item.line_total is None and item.qty > 0 and item.price > 0:
            enriched_items.append(
                item.model_copy(update={"line_total": round(item.price * item.qty)})
            )
        else:
            enriched_items.append(item)
    items = enriched_items

    refined_confidence = max(0.1, min(0.99, confidence + bonuses - penalties))

    return result.model_copy(
        update={
            "merchant": merchant,
            "items": items,
            "total_amount": total,
            "transaction_date": tx_date,
            "ocr_confidence": round(refined_confidence, 3),
        }
    )
