"""Fast Track OCR — regex/heuristic extraction on VietOCR text (when available)."""

import re
from datetime import date, datetime
from typing import Optional

from app.schemas import OcrResult, ReceiptItem

# Vietnamese receipt patterns
AMOUNT_PATTERNS = [
    r"(?:T[OỔO]NG|Tong|TOTAL|Tổng cộng|Tổng tiền)[:\s]*([\d.,]+)\s*(?:đ|VND|vnđ)?",
    r"(?:Thanh toán|THANH TOAN)[:\s]*([\d.,]+)",
    r"([\d.,]+)\s*(?:đ|VND|vnđ)\s*$",
]
DATE_PATTERNS = [
    r"(\d{2}[/-]\d{2}[/-]\d{4})",
    r"(\d{4}[/-]\d{2}[/-]\d{2})",
    r"(\d{2}[/-]\d{2}[/-]\d{2})",
]
MERCHANT_PATTERNS = [
    r"^([A-ZÀ-Ỹa-zà-ỹ\s&'.]+(?:CO\.LTD|LTD|JSC|CP)?)",
]


def _parse_amount(text: str) -> Optional[float]:
    for pattern in AMOUNT_PATTERNS:
        match = re.search(pattern, text, re.IGNORECASE | re.MULTILINE)
        if match:
            raw = match.group(1).replace(".", "").replace(",", "")
            try:
                return float(raw)
            except ValueError:
                continue
    return None


def _parse_date(text: str) -> Optional[date]:
    for pattern in DATE_PATTERNS:
        match = re.search(pattern, text)
        if match:
            raw = match.group(1)
            for fmt in ("%d/%m/%Y", "%d-%m-%Y", "%Y/%m/%d", "%Y-%m-%d", "%d/%m/%y"):
                try:
                    return datetime.strptime(raw, fmt).date()
                except ValueError:
                    continue
    return None


def _parse_merchant(text: str) -> Optional[str]:
    lines = [l.strip() for l in text.split("\n") if l.strip()]
    for line in lines[:5]:
        if len(line) > 3 and not re.match(r"^\d", line):
            if not re.search(r"(đ|VND|tổng|total|ngày|date)", line, re.I):
                return line.strip()
    return lines[0] if lines else None


def _parse_items(text: str) -> list[ReceiptItem]:
    items = []
    item_pattern = r"^(.+?)\s+([\d.,]+)\s*(?:x\s*(\d+))?\s*(?:đ|VND)?$"
    for line in text.split("\n"):
        line = line.strip()
        match = re.match(item_pattern, line, re.I)
        if match:
            name, price_str, qty = match.group(1), match.group(2), match.group(3)
            price = float(price_str.replace(".", "").replace(",", ""))
            items.append(ReceiptItem(name=name.strip(), price=price, qty=int(qty or 1)))
    return items[:20]


def _estimate_confidence(text: str, amount: Optional[float], dt: Optional[date]) -> float:
    score = 0.5
    if amount:
        score += 0.2
    if dt:
        score += 0.15
    if len(text) > 50:
        score += 0.1
    if re.search(r"(đ|VND|tổng|TOTAL)", text, re.I):
        score += 0.05
    return min(score, 0.98)


def _has_local_ocr_engine() -> bool:
    """True when a real on-box OCR engine (VietOCR/DBNet) is wired in."""
    return False


async def run_fast_track(image_bytes: bytes, raw_text_hint: Optional[str] = None) -> OcrResult:
    """
    Extract from OCR text hint or local VietOCR output.
    Without a local engine, returns low confidence so CR-OCR routes to smart track (Vintern/Gemini).
    """
    if raw_text_hint:
        text = raw_text_hint
    elif _has_local_ocr_engine():
        text = await _run_local_ocr(image_bytes)
    else:
        return OcrResult(
            merchant=None,
            items=[],
            total_amount=None,
            transaction_date=None,
            ocr_track_used="fast",
            ocr_confidence=0.0,
            raw_text="",
        )

    amount = _parse_amount(text)
    dt = _parse_date(text)
    merchant = _parse_merchant(text)
    items = _parse_items(text)
    confidence = _estimate_confidence(text, amount, dt)

    return OcrResult(
        merchant=merchant,
        items=items,
        total_amount=amount,
        transaction_date=dt,
        ocr_track_used="fast",
        ocr_confidence=confidence,
        raw_text=text,
    )


async def _run_local_ocr(image_bytes: bytes) -> str:
    """Placeholder for VietOCR + DBNet integration."""
    raise NotImplementedError("Local VietOCR not configured")
