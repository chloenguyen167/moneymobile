"""Regex fallback for Vietnamese bank / e-wallet transfer screenshots."""

from __future__ import annotations

import re
from datetime import date

from app.schemas import PaymentScreenshotExtract
from app.services.ocr.reference_correction import normalize_vietnamese

# Amount with thousand separators (., or space), optionally tagged VND/đ
AMOUNT_SEP_RE = re.compile(
    r"(?<![A-Za-z0-9])([+-]?\d{1,3}(?:[.,\s]\d{3}){1,4})(?!\d)(?:\s*(?:vnd|đ|d\b))?",
    re.IGNORECASE,
)
# Strongest signal: amount immediately before VND/đ
AMOUNT_BEFORE_VND_RE = re.compile(
    r"(?<![A-Za-z0-9])([+-]?\d{1,3}(?:[.,\s]\d{3}){1,4}|\d{5,12})\s*(?:vnd|đ)\b",
    re.IGNORECASE,
)
# Bare integer amount only when tagged with currency
AMOUNT_TAGGED_INT_RE = re.compile(
    r"(?<![A-Za-z0-9])([+-]?\d{4,12})(?!\d)\s*(?:vnd|đ)\b",
    re.IGNORECASE,
)

DATE_PATTERNS = [
    re.compile(r"(\d{2})/(\d{2})/(\d{4})"),
    re.compile(r"(\d{4})-(\d{2})-(\d{2})"),
]
REFERENCE_RE = re.compile(
    r"(?:ma\s*gd|ma\s*giao\s*dich|ref|reference|txn|trace)\s*[:#-]?\s*([a-z0-9]{8,})",
    re.IGNORECASE,
)
BARE_REF_RE = re.compile(r"\b([0-9]{2,4}[A-Z][A-Z0-9]{8,})\b")

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
    "napas": "Napas",
}

MERCHANT_HINT_PREFIXES = [
    "nguoi nhan",
    "nguoi huong",
    "thu huong",
    "den:",
    "to:",
    "merchant",
    "cua hang",
    "don vi nhan",
    "thanh toan toi",
    "chuyen den",
]

# UI chips / banners that must never stick to payee names
UI_BADGE_RE = re.compile(
    r"\b(da\s*luu|da\s*luong|da\s*luon|đã\s*lưu|đã\s*lương|đã\s*luu|saved)\b",
    re.IGNORECASE,
)

SKIP_MERCHANT_RE = re.compile(
    r"(cam on|cảm ơn|mien phi|miễn phí|thanh cong|thành công|"
    r"giao dich khac|trang chu|chuyen khoan mien|"
    r"napas|cach thuc|thoi gian|noi dung|ma giao dich|"
    r"\bvnd\b|www\.|http|"
    r"da\s*luu|da\s*luong|đã\s*lưu)",
    re.I,
)

BANK_CODE_RE = re.compile(
    r"\b(SHB|VCB|TCB|MB|ACB|TPBank|TPB|BIDV|VTB|VPB|MSB|OCB|SEABANK|PVcomBank)\b",
    re.I,
)

SKIP_AMOUNT_LINE_RE = re.compile(
    r"(ma\s*gd|ma\s*giao\s*dich|so\s*tk|stk|tai\s*khoan|account|"
    r"ref|reference|trace|barcode|otp)",
    re.I,
)

MIN_AMOUNT = 1_000.0
MAX_AMOUNT = 50_000_000_000.0  # 50 tỷ


def preprocess_payment_text(raw_text: str | None) -> str | None:
    """Join split hero amounts: '14\\n350\\n000 VND' → '14,350,000 VND'."""
    if not raw_text:
        return raw_text
    t = raw_text
    t = re.sub(
        r"(\d{1,3})\s+(\d{3})\s+(\d{3})\s*(?=\s*(?:vnd|đ)\b)",
        r"\1,\2,\3 ",
        t,
        flags=re.IGNORECASE,
    )
    t = re.sub(
        r"(\d{1,2})\s+(\d{3})\s+(\d{3})\s+(\d{3})\s*(?=\s*(?:vnd|đ)\b)",
        r"\1,\2,\3,\4 ",
        t,
        flags=re.IGNORECASE,
    )
    return t


def parse_payment_screenshot_text(raw_text: str | None) -> PaymentScreenshotExtract:
    text = preprocess_payment_text(raw_text) or ""
    text = text.strip()
    normalized = normalize_vietnamese(text)
    merchant = _extract_merchant(text, normalized)
    total_amount = _extract_amount(text)
    transaction_date = _extract_date(text)
    payment_source = _extract_payment_source(normalized)
    description = _extract_description(text, normalized)
    reference_code = _extract_reference(text, normalized)

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


def _to_amount(raw: str) -> float | None:
    s = raw.strip().replace(" ", "").replace("+", "").replace("\u00a0", "")
    if not s:
        return None
    s = s.replace(".", "").replace(",", "")
    if not s.isdigit():
        return None
    value = float(s)
    if value < MIN_AMOUNT or value > MAX_AMOUNT:
        return None
    return value


def _line_is_amount_noise(line: str) -> bool:
    n = normalize_vietnamese(line)
    if SKIP_AMOUNT_LINE_RE.search(n):
        return True
    if re.search(r"\d{3,5}\s+\d{3,5}\s+\d{2,5}", line) and "vnd" not in n and "đ" not in line.lower():
        return True
    if re.search(r"\d{2,}[A-Za-z][A-Za-z0-9]{4,}", line):
        return True
    return False


def _extract_amount(text: str) -> float | None:
    """Prefer VND-tagged separator amounts; never max(account, txn id)."""
    scored: list[tuple[int, float]] = []

    # Pass 1: amounts glued to VND/đ (highest priority)
    for match in AMOUNT_BEFORE_VND_RE.finditer(text):
        value = _to_amount(match.group(1))
        if value is None:
            continue
        window = text[max(0, match.start() - 30) : match.end() + 5]
        if _line_is_amount_noise(window) and value >= 1_000_000_000:
            continue
        score = 100
        if value >= 10_000:
            score += 20
        if value >= 100_000_000_000:
            score -= 100
        scored.append((score, value))

    for line in text.splitlines() or [text]:
        line = line.strip()
        if not line:
            continue
        noisy = _line_is_amount_noise(line)
        n = normalize_vietnamese(line)
        has_currency = bool(re.search(r"\bvnd\b|đ", n, re.I)) or "vnd" in line.lower() or "đ" in line

        for match in AMOUNT_SEP_RE.finditer(line):
            value = _to_amount(match.group(1))
            if value is None:
                continue
            if noisy and not has_currency:
                continue
            score = 10
            if has_currency:
                score += 50
            if "vnd" in match.group(0).lower() or "đ" in match.group(0):
                score += 30
            if value >= 10_000:
                score += 15
            if value < 1_000_000_000:
                score += 10
            if value >= 100_000_000_000:
                score -= 80
            # Tiny amounts without clear currency are weak (OCR fragments like 4,350)
            if value < 10_000 and not has_currency:
                score -= 40
            scored.append((score, value))

        for match in AMOUNT_TAGGED_INT_RE.finditer(line):
            value = _to_amount(match.group(1))
            if value is None:
                continue
            scored.append((90 if value >= 10_000 else 50, value))

    if not scored:
        return None

    # Prefer highest score; ties → larger amount (hero transfer total)
    scored.sort(key=lambda x: (-x[0], -x[1]))
    best_score, best_value = scored[0]

    # If a much larger VND-tagged candidate exists within close score, prefer it
    # (guards smart/OCR returning 4,350 while 14,350,000 VND is present)
    for score, value in scored:
        if score >= best_score - 30 and value > best_value * 10 and value >= 10_000:
            best_value = value
            break

    return best_value


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


def _extract_reference(text: str, normalized: str) -> str | None:
    match = REFERENCE_RE.search(normalized)
    if match:
        return match.group(1).strip().upper()
    match = BARE_REF_RE.search(text)
    if match:
        return match.group(1).strip().upper()
    return None


def _extract_payment_source(normalized: str) -> str | None:
    for keyword, label in SOURCE_KEYWORDS.items():
        if keyword in normalized:
            return label
    return None


def _clean_person_name(line: str) -> str:
    raw = UI_BADGE_RE.sub(" ", line)
    raw = BANK_CODE_RE.sub(" ", raw)
    raw = re.sub(r"[\d|.,]+", " ", raw)
    raw = re.sub(r"\s{2,}", " ", raw).strip(" -|")
    return raw


def _looks_like_person_name(line: str) -> bool:
    raw = _clean_person_name(line)
    if len(raw) < 5 or len(raw) > 80:
        return False
    if SKIP_MERCHANT_RE.search(raw):
        return False
    letters = re.findall(r"[A-Za-zÀ-ỹ]", raw)
    if len(letters) < 4:
        return False
    words = [w for w in re.split(r"\s+", raw) if w]
    if not (2 <= len(words) <= 6):
        return False
    return True


def _person_name_from_line(line: str) -> str | None:
    if not _looks_like_person_name(line):
        return None
    raw = _clean_person_name(line)
    return raw[:80] if len(raw) >= 5 else None


def clean_payment_merchant_name(name: str | None) -> str | None:
    """Public cleaner for merge / LLM outputs."""
    if not name:
        return None
    cleaned = _person_name_from_line(name)
    if cleaned:
        return cleaned
    raw = UI_BADGE_RE.sub(" ", name)
    raw = re.sub(r"\s{2,}", " ", raw).strip(" -|")
    if not raw or SKIP_MERCHANT_RE.search(raw):
        return None
    return raw[:80]


def _extract_merchant(text: str, normalized: str) -> str | None:
    lines = [line.strip() for line in text.splitlines() if line.strip()]
    normalized_lines = [normalize_vietnamese(line) for line in lines]

    for index, line in enumerate(normalized_lines):
        if any(prefix in line for prefix in MERCHANT_HINT_PREFIXES):
            original = lines[index]
            parts = re.split(r"[:\-]", original, maxsplit=1)
            candidate = parts[1].strip() if len(parts) > 1 else original.strip()
            if index + 1 < len(lines):
                nxt = _person_name_from_line(lines[index + 1])
                if nxt:
                    return nxt
            cleaned = _person_name_from_line(candidate)
            if cleaned:
                return cleaned

    for index, line in enumerate(lines):
        if BANK_CODE_RE.search(line):
            named = _person_name_from_line(line)
            if named:
                return named
            if index > 0:
                prev = _person_name_from_line(lines[index - 1])
                if prev:
                    return prev

    names = [n for ln in lines if (n := _person_name_from_line(ln))]
    if len(names) >= 2:
        return names[-1]
    if len(names) == 1:
        return names[0]
    return None


def _extract_description(text: str, normalized: str) -> str | None:
    lines = [line.strip() for line in text.splitlines() if line.strip()]
    for index, line in enumerate(lines):
        normalized_line = normalize_vietnamese(line)
        if "noi dung" in normalized_line or "message" in normalized_line or "content" in normalized_line:
            parts = re.split(r"[:\-]", line, maxsplit=1)
            if len(parts) > 1 and parts[1].strip():
                return parts[1].strip()[:120]
            rest = re.sub(
                r"(?i)(n[oộ]i\s*dung|message|content)\s*[:\-]?\s*",
                "",
                line,
            ).strip()
            if rest and not re.match(r"\d{1,2}/\d{1,2}/\d{2,4}$", rest):
                if "thoi gian" not in normalize_vietnamese(rest):
                    return rest[:120]
            if index + 1 < len(lines):
                nxt = lines[index + 1].strip()
                if nxt and not SKIP_MERCHANT_RE.search(nxt) and "thoi gian" not in normalize_vietnamese(nxt):
                    if not re.match(r"\d{1,2}/\d{1,2}/\d{2,4}$", nxt):
                        return nxt[:120]
            return None
    return None
