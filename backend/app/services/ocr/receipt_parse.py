"""Parse Vietnamese receipt OCR text → merchant / date / items / total.

Handles supermarket column layouts (WinMart, BHX, …) and simple cafe receipts.
Tolerant of common VietOCR character errors.
"""

from __future__ import annotations

import re
from datetime import date, datetime
from typing import Optional

from app.schemas import ReceiptItem
from app.services.ocr.reference_correction import normalize_vietnamese

KNOWN_MERCHANTS = [
    "winmart",
    "win mart",
    "bach hoa xanh",
    "bách hóa xanh",
    "coopmart",
    "coop mart",
    "big c",
    "bigc",
    "lotte",
    "aeon",
    "circle k",
    "gs25",
    "ministop",
    "family mart",
    "phuc long",
    "phúc long",
    "highlands",
    "starbucks",
    "the coffee house",
]

SKIP_LINE_RE = re.compile(
    r"(mặt hàng|mat hang|đơn giá|don gia|\bgiá\b|\bsl\b|t\.?\s*ti[eề]n|"
    r"phiếu tính|phieu tinh|xin cảm|xin cam|quét qr|quet qr|xuathoadon|"
    r"mã cqt|ma cqt|\bptt\b|\bmsch\b|\bnv\b|barcode|www\.|http|"
    r"đơn hoặc|truy cập|truy cap|"
    r"s[ốo]\s*h[đd]|so\s*hd|invoice|mã\s*h[đd]|ma\s*hd|"
    r"cảm ơn|cam on|hẹn gặp|hen gap|quý khách|quy khach|"
    r"vui lòng|vui long|khảo sát|khao sat|feedback|"
    r"\bcash\b|\bvnd\b|tiền mặt|tien mat)",
    re.I,
)

# Names that must never become line items
JUNK_ITEM_NAME_RE = re.compile(
    r"(s[ốo]\s*h[đd]|so\s*hd|invoice|"
    r"tổng\s*tiền|tong\s*tien|thành\s*tiền|thanh\s*tien|tổng\s*cộng|tong\s*cong|"
    r"cảm ơn|cam on|hẹn gặp|hen gap|vui lòng|vui long|khảo sát|khao sat|"
    r"quý khách|quy khach|cung cấp thông tin|cung cap thong tin|"
    r"\bcash\b|\bchange\b|phải trả|phai tra|thanh toán|thanh toan|"
    r"khách trả|khach tra|zalopay|momo|vnpay|vietqr|"
    r"tiền mặt|tien mat|tiền thừa|tien thua|subtotal|total tax|"
    r"www\.|http|phuclong-khaosat)",
    re.I,
)

# Invoice / receipt id patterns (avoid treating id digits as money)
INVOICE_ID_RE = re.compile(
    r"(s[ốo]\s*h[đd]|so\s*hd|invoice|mã\s*h[đd]|ma\s*hd|"
    r"\bCH\d{3,}|[A-Z]{1,4}\d{3,}[-/]\d{3,})",
    re.I,
)

DATE_PATTERNS = [
    r"(\d{1,2}[/-]\d{1,2}[/-]\d{4})(?:\s+(\d{1,2}:\d{2})(?::\d{2})?)?",
    r"(\d{4}[/-]\d{1,2}[/-]\d{1,2})",
]

MONEY_TOKEN_RE = re.compile(r"(?<!\d)(\d{1,3}(?:[.,]\d{3})+|\d{4,8})(?!\d)")


def _norm(text: str) -> str:
    return normalize_vietnamese(text or "")


def _normalize_money_token(raw: str) -> Optional[float]:
    s = raw.strip().replace(" ", "")
    if not s:
        return None
    # Leading 0.xxx / 0,xxx are kg quantities, never VND
    if re.match(r"^0[.,]\d+$", s):
        return None
    if "," in s and "." in s:
        if s.rfind(",") > s.rfind("."):
            s = s.replace(".", "").replace(",", ".")
        else:
            s = s.replace(",", "")
    else:
        s = s.replace(",", "").replace(".", "")
    if not s.isdigit():
        try:
            value = float(s)
        except ValueError:
            return None
    else:
        if len(s) > 8 or (s.startswith("0") and len(s) > 5):
            return None
        value = float(s)
    if value < 100 or value > 50_000_000:
        return None
    # Years misread as money (e.g. 2026 on date lines)
    if 1900 <= value <= 2100:
        return None
    return value


def _is_vn_price_token(raw: str) -> bool:
    """True when token is a VND thousand-group (20,200 / 20.200), not kg qty."""
    s = raw.strip()
    if re.match(r"^\d{2,}[.,]\d{3}$", s):
        return True
    if "," in s:
        parts = s.split(",")
        if len(parts) >= 2 and all(len(p) == 3 for p in parts[1:]):
            return True
    if "." in s:
        parts = s.split(".")
        if len(parts) >= 2 and all(len(p) == 3 for p in parts[1:]) and len(parts[0]) >= 2:
            return True
    return False


def _peel_leading_qty(line: str) -> tuple[Optional[float], str]:
    """Peel kg/unit qty at start of amount rows: '0.87 80,000 69,600'."""
    m = re.match(r"^(\d+[.,]\d+)\s+(.*)$", line.strip())
    if not m:
        return None, line
    raw = m.group(1)
    if _is_vn_price_token(raw):
        return None, line
    try:
        qty = float(raw.replace(",", "."))
    except ValueError:
        return None, line
    if 0 < qty < 10:
        return qty, m.group(2)
    return None, line


def _extract_money_values(text: str) -> list[float]:
    values: list[float] = []
    for match in MONEY_TOKEN_RE.finditer(text):
        amount = _normalize_money_token(match.group(1))
        if amount is not None:
            values.append(amount)
    return values


def _is_tender_or_change_line(line: str) -> bool:
    """Cash tender / change — NOT the amount customer must pay."""
    n = _norm(line)
    if re.search(r"\bchange\b|tien thua|tiền thừa|tra lai|trả lại", n):
        return True
    if re.search(r"\bcash\b|tien mat|tiền mặt|tien ca the|tiền cà thẻ", n):
        # "CASH(VND) 125,000" when cash == total is still tender; exclude as total source
        return True
    if "tien mat" in n or "tien dua" in n or "khach dua" in n:
        return True
    # Payment channel: "Khach tra ZaloPay 63,000"
    if re.search(r"khach tra|zalopay|momo|vnpay|vietqr|chuyen khoan", n):
        return True
    return False


def _is_payment_total_line(line: str) -> bool:
    n = _norm(line)
    if _is_tender_or_change_line(line):
        return False
    # Column headers: "Ten hang SL Don gia Thanh tien"
    if re.search(r"\b(ten hang|mat hang|item name|don gia|\bsl\b|qty|amount)\b", n) and not _extract_money_values(line):
        return False
    if "thanh toan" in n or "phai tra" in n or "khach phai tra" in n:
        return "giam" not in n or "thanh toan" in n
    if "grand total" in n or "amount due" in n or "amount payable" in n:
        return True
    # English "Total" but not Subtotal / Total tax
    if re.search(r"(?<!sub)\btotals?\b", n) and "tax" not in n and "subtotal" not in n:
        return True
    if re.search(r"\btong\s*cong\b", n):
        return True
    # "tong tien" / "thanh tien" but not discount / order-value subtotal / headers
    if re.search(r"\b(tong\s*tien|thanh\s*tien)\b", n):
        if "giam" in n or "gia tri" in n:
            return False
        if "don gia" in n or "ten hang" in n:
            return False
        return True
    return False


def _total_line_priority(line: str) -> int:
    """Lower = better. Prefer payable amount over subtotal-like tong cong."""
    n = _norm(line)
    if "phai tra" in n or "khach phai tra" in n:
        return 0
    if "thanh toan" in n:
        return 1
    if re.search(r"(?<!sub)\btotals?\b", n) and "tax" not in n:
        return 2
    if "thanh tien" in n or "tong tien" in n:
        return 3
    if "tong cong" in n or "grand total" in n:
        return 4
    return 5


def is_junk_item_name(name: str) -> bool:
    """True for headers/footers/invoice ids that must not become products."""
    raw = (name or "").strip()
    if not raw or len(raw) < 2:
        return True
    if JUNK_ITEM_NAME_RE.search(raw):
        return True
    if INVOICE_ID_RE.search(raw) and not re.search(r"[A-Za-zÀ-ỹ]{3,}", re.sub(r"(s[ốo]\s*h[đd]|so\s*hd|CH\d+)", "", raw, flags=re.I)):
        return True
    # Very long OCR blob = footer / thank-you paragraph
    if len(raw) > 70 and (
        "cam on" in _norm(raw)
        or "cam ơn" in raw.lower()
        or "vui long" in _norm(raw)
        or "hen gap" in _norm(raw)
    ):
        return True
    if len(raw) > 90:
        return True
    return False


def _is_subtotal_line(line: str) -> bool:
    n = _norm(line)
    return (
        "gia tri" in n
        or "tam tinh" in n
        or "tong gia" in n
        or "subtotal" in n
        or "sub total" in n
    )


def _is_discount_line(line: str) -> bool:
    n = _norm(line)
    if re.match(r"^(km|giam)\b", n):
        return True
    return "tien giam" in n or "khuyen mai" in n or n.startswith("km:")


def parse_receipt_date(text: str) -> Optional[date]:
    for pattern in DATE_PATTERNS:
        match = re.search(pattern, text)
        if not match:
            continue
        raw = match.group(1)
        for fmt in ("%d/%m/%Y", "%d-%m-%Y", "%Y/%m/%d", "%Y-%m-%d", "%d/%m/%y", "%d-%m-%y"):
            try:
                return datetime.strptime(raw, fmt).date()
            except ValueError:
                continue
    return None


def parse_receipt_total(text: str) -> Optional[float]:
    lines = [ln.strip() for ln in text.splitlines() if ln.strip()]
    candidates: list[tuple[int, float]] = []

    for i, line in enumerate(lines):
        if not _is_payment_total_line(line):
            continue
        amounts = _extract_money_values(line)
        amount = amounts[-1] if amounts else None
        if amount is None:
            for nxt in lines[i + 1 : i + 3]:
                if _is_discount_line(nxt) or _is_subtotal_line(nxt) or _is_tender_or_change_line(nxt):
                    continue
                nxt_amounts = _extract_money_values(nxt)
                if nxt_amounts:
                    amount = nxt_amounts[-1]
                    break
        if amount is not None:
            candidates.append((_total_line_priority(line), amount))

    if candidates:
        candidates.sort(key=lambda x: x[0])
        return candidates[0][1]

    for line in lines:
        if _is_subtotal_line(line):
            amounts = _extract_money_values(line)
            if amounts:
                return amounts[-1]

    bottom_amounts = _extract_money_values("\n".join(lines[-8:]))
    # Avoid picking Cash from the bottom when labeled totals failed
    return bottom_amounts[-1] if bottom_amounts else None


def parse_receipt_merchant(text: str) -> Optional[str]:
    lines = [ln.strip() for ln in text.splitlines() if ln.strip()]
    joined = _norm(text)

    # Prefer earlier + longer known brand (avoid address "Co.opmart" beating "Phúc Long")
    ranked: list[tuple[int, int, str]] = []
    for known in KNOWN_MERCHANTS:
        kn = _norm(known)
        if kn not in joined:
            continue
        for idx, line in enumerate(lines[:14]):
            if kn in _norm(line):
                ranked.append((idx, -len(kn), line))
                break
    if ranked:
        ranked.sort()
        line = ranked[0][2]
        return re.split(r"\s{2,}|\|", line)[0].strip()[:60]

    for line in lines[:8]:
        if SKIP_LINE_RE.search(line) or _is_payment_total_line(line) or _is_subtotal_line(line):
            continue
        if parse_receipt_date(line):
            continue
        if re.match(r"^[\d\s.,:\-\[\]|]+$", line):
            continue
        if len(line) < 3:
            continue
        return line[:80]
    return None


def _is_meta_line(line: str) -> bool:
    if SKIP_LINE_RE.search(line):
        return True
    if INVOICE_ID_RE.search(line):
        return True
    if _is_tender_or_change_line(line):
        return True
    if _is_payment_total_line(line) or _is_subtotal_line(line):
        return True
    if _is_discount_line(line):
        return True
    if is_junk_item_name(line):
        return True
    n = _norm(line)
    if n in {_norm(m) for m in KNOWN_MERCHANTS}:
        return True
    if re.search(r"phieu tinh|hoa don|phieu thanh toan", n):
        return True
    return False


def _split_name_and_amounts(line: str) -> tuple[str, list[float]]:
    amounts = _extract_money_values(line)
    name = line
    matches = list(MONEY_TOKEN_RE.finditer(line))
    if matches:
        # Strip from first money token that starts the trailing numeric block
        first_money_idx = None
        for match in matches:
            if _normalize_money_token(match.group(1)) is None:
                continue
            tail = line[match.start() :]
            cleaned_tail = (
                tail.replace("đ", "")
                .replace("VND", "")
                .replace("vnđ", "")
                .replace("D", "")
                .replace("d", "")
            )
            if re.fullmatch(r"[\d\s.,|:\-A-Za-z]{0,16}", cleaned_tail) or re.fullmatch(
                r"[\d\s.,|:\-]*[A-Za-z]{0,3}", cleaned_tail
            ):
                first_money_idx = match.start()
                break
        if first_money_idx is not None:
            # Include leading qty digit(s) just before price: "... (L) 1 50,000"
            prefix = line[:first_money_idx]
            qty_prefix = re.search(r"^(.*?)(?:\s+\d{1,3}\s*)$", prefix)
            if qty_prefix and re.search(r"[A-Za-zÀ-ỹ]", qty_prefix.group(1)):
                name = qty_prefix.group(1)
            else:
                name = prefix
    name = re.sub(r"[\s|]+$", "", name).strip(" -|:")
    name = re.sub(r"\s{2,}", " ", name)
    name = re.sub(r"\b(Ns|Consersed|Blolo)\b", "", name, flags=re.I)
    # Close unfinished size markers from OCR: "(L D" / "(L"
    name = re.sub(r"\(\s*[Ll]\s*[Dd]?\s*$", "", name)
    name = re.sub(r"\s{2,}", " ", name).strip(" -|(")
    return name, amounts


def _amounts_to_item_fields(amounts: list[float]) -> tuple[float, float, Optional[float]]:
    """Return (line_total, qty, unit_price)."""
    if len(amounts) >= 3:
        a, b, c = amounts[0], amounts[1], amounts[2]
        # qty, unit_price, line_total (BHX when qty slipped into money tokens)
        if a < 1000 and b >= 1000 and c >= 1000:
            return float(c), float(a if a > 0 else 1.0), float(b)
        # unit_price, qty, line_total
        unit_price, qty_raw, line_total = a, b, c
        if qty_raw >= 1000:
            return amounts[-1], 1.0, amounts[0]
        qty = qty_raw if 0 < qty_raw < 1000 else 1.0
        return float(line_total), float(qty), float(unit_price)
    if len(amounts) == 2:
        a, b = amounts
        # Cafe OCR: qty then line total — "1 55,000"
        if a < 100 and b >= 1000:
            return float(b), float(a if a > 0 else 1.0), float(b / a) if a else float(b)
        # Common WinMart OCR: unit_price, qty (missing line total)
        if b < 1000:
            return float(a * b if b > 0 else a), float(b), float(a)
        # unit_price, line_total → infer qty (supports kg decimals)
        qty = round(b / a, 3) if a else 1.0
        if qty <= 0 or qty > 100:
            qty = 1.0
        return float(b), float(qty), float(a)
    return float(amounts[0]), 1.0, float(amounts[0])


def parse_receipt_items(text: str) -> list[ReceiptItem]:
    """Extract items. `price` = thành tiền; `unit_price` = đơn giá when known."""
    lines = [ln.strip() for ln in text.splitlines() if ln.strip()]
    items: list[ReceiptItem] = []
    receipt_total = parse_receipt_total(text)

    current_names: list[str] = []
    current_amounts: list[float] = []

    def flush() -> None:
        nonlocal current_names, current_amounts
        if not current_amounts:
            current_names = []
            return
        name = re.sub(r"\s{2,}", " ", " ".join(current_names)).strip()
        current_names = []
        amounts = current_amounts
        current_amounts = []
        if not name or len(name) < 2:
            return
        if is_junk_item_name(name):
            return
        if _is_meta_line(name) or _is_payment_total_line(name) or _is_subtotal_line(name):
            return
        if _is_discount_line(name):
            return
        line_total, qty, unit_price = _amounts_to_item_fields(amounts)
        # Only rewrite bogus invoice-id fractions (e.g. 11801/8502), keep real kg qty
        if (
            qty != int(qty)
            and (qty > 50 or qty < 0.01)
            and len(amounts) >= 2
            and all(a >= 1000 for a in amounts[:2])
        ):
            line_total, qty, unit_price = float(amounts[-1]), 1.0, float(amounts[-1])
        items.append(
            ReceiptItem(
                name=name[:120],
                price=line_total,
                qty=qty,
                unit_price=unit_price,
            )
        )

    for line in lines:
        if _is_meta_line(line) or INVOICE_ID_RE.search(line):
            # Always flush pending product before skipping headers/totals
            flush()
            continue

        # Peel promotion/discount tail: ".... KM: -3,100"
        line = re.sub(r"\bKM\s*:?\s*[-−]?\s*[\d.,]+", "", line, flags=re.I).strip()
        if not line:
            continue
        if _is_discount_line(line):
            continue

        # WinMart 3-col amount row: "20,200 1 20,200" (unit_price qty line_total)
        if not re.search(r"[A-Za-zÀ-ỹ]", line):
            row_amounts = _extract_money_values(line)
            if (
                len(row_amounts) == 3
                and row_amounts[0] >= 1000
                and row_amounts[2] >= 1000
                and 1 <= row_amounts[1] <= 99
                and current_names
                and not current_amounts
            ):
                unit_price, qty, line_total = row_amounts[0], row_amounts[1], row_amounts[2]
                item_name = re.sub(r"\s{2,}", " ", " ".join(current_names)).strip()
                current_names = []
                if item_name and not is_junk_item_name(item_name):
                    items.append(
                        ReceiptItem(
                            name=item_name[:120],
                            price=float(line_total),
                            qty=float(qty),
                            unit_price=float(unit_price),
                        )
                    )
                continue

        # Amount-only row with leading decimal qty: "0.87 80,000 69,600" / "1.174 42,000 49,308"
        if not re.search(r"[A-Za-zÀ-ỹ]", line):
            qty_prefix, rest = _peel_leading_qty(line)
            if qty_prefix is not None and current_names and not current_amounts:
                rest_amounts = _extract_money_values(rest)
                if rest_amounts:
                    line_total, _, unit_price = _amounts_to_item_fields(rest_amounts)
                    qty = qty_prefix
                    if len(rest_amounts) >= 2 and rest_amounts[0] >= 1000:
                        unit_price = float(rest_amounts[0])
                        line_total = float(rest_amounts[-1])
                    elif len(rest_amounts) == 1:
                        line_total = float(rest_amounts[0])
                        unit_price = round(line_total / qty, 2) if qty else line_total
                    item_name = re.sub(r"\s{2,}", " ", " ".join(current_names)).strip()
                    current_names = []
                    current_amounts = []
                    if item_name and not is_junk_item_name(item_name):
                        items.append(
                            ReceiptItem(
                                name=item_name[:120],
                                price=line_total,
                                qty=qty,
                                unit_price=unit_price,
                            )
                        )
                    continue

        name, amounts = _split_name_and_amounts(line)
        # Strip trailing bare qty / "1.00" glued into name
        name = re.sub(r"\s+\d+(?:[.,]\d+)?$", "", name).strip() if amounts else name
        has_alpha = bool(re.search(r"[A-Za-zÀ-ỹ]", name))

        if amounts and has_alpha:
            flush()
            current_names = [name] if name else []
            current_amounts = amounts
            # Same-line complete item — flush immediately so totals don't wipe it
            flush()
            continue

        if amounts and not has_alpha:
            if current_names and not current_amounts:
                current_amounts = amounts
                flush()
            continue

        if has_alpha and not amounts:
            n = _norm(name)
            # Skip date / staff / doc-id header lines as item names
            if parse_receipt_date(line) or re.search(r"\b(ngay|gio|nhan vien|so ct)\b", n):
                continue
            if is_junk_item_name(name):
                continue
            # Header-ish
            if re.search(r"item name|ten hang|mat hang", n):
                continue
            current_names.append(name)
            if len(current_names) > 3:
                current_names = current_names[-3:]
            continue

    flush()

    unique: list[ReceiptItem] = []
    seen: set[tuple] = set()
    for item in items:
        if is_junk_item_name(item.name):
            continue
        # Drop footer/total duplicate priced at receipt total
        if (
            receipt_total
            and abs(item.price - receipt_total) < 1
            and (len(item.name) > 40 or is_junk_item_name(item.name))
        ):
            continue
        key = (item.name.lower()[:40], round(item.price), round(float(item.qty), 3))
        if key in seen:
            continue
        seen.add(key)
        unique.append(item)

    # If sum still ~2x total, drop items equal to total with long/junk names
    if receipt_total and unique:
        s = sum(i.price for i in unique)
        if s > receipt_total * 1.35:
            trimmed = [
                i
                for i in unique
                if not (
                    abs(i.price - receipt_total) < 1
                    and (len(i.name) > 35 or JUNK_ITEM_NAME_RE.search(i.name))
                )
            ]
            if trimmed:
                unique = trimmed

    return unique[:40]


def estimate_parse_confidence(
    text: str,
    amount: Optional[float],
    dt: Optional[date],
    items: list[ReceiptItem],
    merchant: Optional[str],
) -> float:
    if not (text or "").strip():
        return 0.0
    score = 0.4
    if merchant:
        score += 0.1
    if amount:
        score += 0.2
    if dt:
        score += 0.15
    if items:
        score += min(0.2, 0.05 * len(items))
    if len(text) > 80:
        score += 0.05
    return min(score, 0.98)
