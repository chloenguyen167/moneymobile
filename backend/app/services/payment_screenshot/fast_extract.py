import re
from datetime import date

from app.schemas import PaymentScreenshotExtract
from app.services.ocr.reference_correction import normalize_vietnamese

AMOUNT_RE = re.compile(
    r"(?<!\d)(?:vnd\s*)?([+-]?\d{1,3}(?:[.,]\d{3})+|[+-]?\d{4,})(?:\s*(?:d|vnd|đ))?",
    re.IGNORECASE,
)
DATE_PATTERNS = [
    re.compile(r"(\d{2})/(\d{2})/(\d{4})"),
    re.compile(r"(\d{4})-(\d{2})-(\d{2})"),
]
REFERENCE_RE = re.compile(r"\b(?:ma gd|ma giao dich|ref|reference|txn)\s*[:#-]?\s*([a-z0-9-]{6,})", re.IGNORECASE)

SOURCE_KEYWORDS = {
    "momo": "MoMo",
    "zalopay": "ZaloPay",
    "shopeepay": "ShopeePay",
    "viettel money": "Viettel Money",
    "viettelmoney": "Viettel Money",
    "mb bank": "MB Bank",
    "mbbank": "MB Bank",
    "techcombank": "Techcombank",
    "vcb": "Vietcombank",
    "vietcombank": "Vietcombank",
    "tpbank": "TPBank",
    "acb": "ACB",
}

MERCHANT_HINT_PREFIXES = [
    "nguoi nhan",
    "nguoi huong",
    "merchant",
    "cua hang",
    "don vi nhan",
    "thanh toan toi",
    "chuyen den",
]


def parse_payment_screenshot_text(raw_text: str | None) -> PaymentScreenshotExtract:
    text = (raw_text or "").strip()
    normalized = normalize_vietnamese(text)
    merchant = _extract_merchant(text, normalized)
    total_amount = _extract_amount(text)
    transaction_date = _extract_date(text)
    payment_source = _extract_payment_source(normalized)
    description = _extract_description(text, normalized)
    reference_code = _extract_reference(text)

    return PaymentScreenshotExtract(
        merchant=merchant,
        total_amount=total_amount,
        transaction_date=transaction_date,
        payment_source=payment_source,
        description=description,
        reference_code=reference_code,
        ocr_track_used="payment_fast",
        ocr_confidence=0.65 if any([merchant, total_amount, transaction_date]) else 0.35,
        raw_text=text or None,
    )


def _extract_amount(text: str) -> float | None:
    matches = []
    for match in AMOUNT_RE.finditer(text):
        raw = match.group(1).replace(".", "").replace(",", "").replace("+", "")
        try:
            value = float(raw)
        except ValueError:
            continue
        if value <= 0:
            continue
        matches.append(value)
    return max(matches) if matches else None


def _extract_date(text: str) -> date | None:
    for pattern in DATE_PATTERNS:
        match = pattern.search(text)
        if not match:
            continue
        try:
            if pattern.pattern.startswith("(\\d{2})"):
                day, month, year = map(int, match.groups())
                return date(year, month, day)
            year, month, day = map(int, match.groups())
            return date(year, month, day)
        except ValueError:
            continue
    return None


def _extract_reference(text: str) -> str | None:
    match = REFERENCE_RE.search(text)
    return match.group(1).strip() if match else None


def _extract_payment_source(normalized: str) -> str | None:
    for keyword, label in SOURCE_KEYWORDS.items():
        if keyword in normalized:
            return label
    return None


def _extract_merchant(text: str, normalized: str) -> str | None:
    lines = [line.strip() for line in text.splitlines() if line.strip()]
    normalized_lines = [normalize_vietnamese(line) for line in lines]
    for index, line in enumerate(normalized_lines):
        if any(prefix in line for prefix in MERCHANT_HINT_PREFIXES):
            original = lines[index]
            parts = re.split(r"[:\-]", original, maxsplit=1)
            candidate = parts[1].strip() if len(parts) > 1 else original.strip()
            if candidate:
                return candidate
    for index, line in enumerate(normalized_lines):
        if "thanh toan" in line or "chuyen khoan" in line:
            return lines[index]
    return None


def _extract_description(text: str, normalized: str) -> str | None:
    lines = [line.strip() for line in text.splitlines() if line.strip()]
    for index, line in enumerate(lines):
        normalized_line = normalize_vietnamese(line)
        if "noi dung" in normalized_line or "message" in normalized_line:
            parts = re.split(r"[:\-]", line, maxsplit=1)
            return parts[1].strip() if len(parts) > 1 else line
    if "thanh toan" in normalized or "chuyen khoan" in normalized:
        return next((line for line in lines if len(line) > 10), None)
    return None
