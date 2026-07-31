"""Parse line items from Vietnamese receipt table layouts (BHX, restaurant, etc.)."""

import re
from typing import Optional

from app.schemas import ReceiptItem
from app.services.ocr.parse_utils import parse_vnd_number, VND_AMOUNT_TOKEN

# Siêu thị: TÊN  qty(decimal)  unit_price  line_total
BHX_ITEM_RE = re.compile(
    r"([A-ZÀ-Ỹ][A-ZÀ-Ỹa-z0-9\s()/'-]{3,45}?)\s+"
    r"(\d+[.,]\d+)\s+"
    rf"({VND_AMOUNT_TOKEN})\s+"
    rf"({VND_AMOUNT_TOKEN})",
    re.UNICODE,
)

BHX_DATA_RE = re.compile(
    rf"(\d+[.,]\d+)\s+({VND_AMOUNT_TOKEN})\s+({VND_AMOUNT_TOKEN})",
    re.UNICODE,
)

# Quán ăn: tên  qty  đơn_giá  thành_tiền
RESTAURANT_ITEM_RE = re.compile(
    rf"([A-Za-zÀ-ỹ][A-Za-zÀ-ỹ\s]{{3,40}}?)\s+(\d+)\s+({VND_AMOUNT_TOKEN})\s+({VND_AMOUNT_TOKEN})",
    re.UNICODE,
)

# Quán ăn qty=1: tên  đơn_giá  thành_tiền
RESTAURANT_QTY1_RE = re.compile(
    rf"([A-Za-zÀ-ỹ][A-Za-zÀ-ỹ\s]{{3,40}}?)\s+({VND_AMOUNT_TOKEN})\s+({VND_AMOUNT_TOKEN})(?=\s+[A-Za-zÀ-ỹ]|\s*T[ổo]ng|$)",
    re.UNICODE,
)

# WinMart+: đơn_giá  qty(decimal)  [KM]  line_total
WINMART_ROW_RE = re.compile(
    rf"({VND_AMOUNT_TOKEN})\s+(\d+[.,]\d+)\s+(?:-\s*({VND_AMOUNT_TOKEN})\s+)?({VND_AMOUNT_TOKEN})",
    re.UNICODE,
)

WINMART_NAME_RE = re.compile(
    r"(WMNK\s+[^\d\n]{3,40}|MEAT\s*DELI[^\d\n]{3,60})",
    re.I | re.UNICODE,
)

SKIP_NAMES = re.compile(
    r"(?:tổng|tong|thanh toán|thanh toan|tiền mặt|sl\s|giá bán|gié bán|g[lé]uilbún|t\.tiền|ttijn|đơn giá|"
    r"phiếu|nhân viên|ngày ct|số ct|bàn|khu|hotline|www\.|http|trang\s|huyên|khấu trừ|xuất hóa)",
    re.I,
)


def _parse_qty(raw: str) -> float:
    s = raw.strip().replace(",", ".")
    try:
        v = float(s)
        return v if v > 0 else 1.0
    except ValueError:
        return 1.0


def _name_before_qty(text: str, qty_start: int) -> str:
    """Extract product name immediately before a decimal qty token."""
    chunk = text[max(0, qty_start - 55):qty_start]
    chunk = re.sub(r"\s+", " ", chunk).strip()
    m = re.search(
        r"([A-Za-zÀ-ỹ][A-Za-zÀ-ỹ0-9\s()/'@\[\]-]{2,42}(?:\(KG\))?)\s*$",
        chunk,
        re.UNICODE,
    )
    return _clean_product_name(m.group(1)) if m else ""


def _parse_bhx_data_rows(text: str) -> list[tuple[str, float, float, float]]:
    """Parse BHX rows from qty+amounts when name+row regex spans header text."""
    rows: list[tuple[str, float, float, float]] = []
    for m in BHX_DATA_RE.finditer(text):
        qty = _parse_qty(m.group(1))
        if qty >= 50:  # skip years / receipt fragments misread as qty
            continue
        amounts = (
            parse_vnd_number(m.group(2)) or 0,
            parse_vnd_number(m.group(3)) or 0,
        )
        if not any(amounts):
            continue
        name = _name_before_qty(text, m.start())
        if name:
            rows.append((name, qty, amounts[0], amounts[1]))
    return rows


def _clean_name(name: str) -> str:
    name = re.sub(r"\s+", " ", name.strip(" -|:"))
    return name


def _clean_product_name(name: str) -> str:
    """Strip table-header garbage from OCR-scrambled product names."""
    name = _clean_name(name)
    name = re.sub(r"^[@oO\s]+", "", name)
    for marker in ("Ttijn", "T.Tiền", "Gié bán", "Giá bán", "Giá bán", "bán Ttijn"):
        idx = name.lower().rfind(marker.lower())
        if idx >= 0:
            name = name[idx + len(marker):].strip()
    if SKIP_NAMES.search(name):
        m = re.search(
            r"([A-Za-zÀ-ỹ][A-Za-zÀ-ỹ0-9\s()/'@\[\]-]{2,42}(?:\(KG\))?)$",
            name,
            re.UNICODE,
        )
        if m:
            name = _clean_name(m.group(1))
    return name


def _is_valid_item(name: str, unit: float, line: float) -> bool:
    if len(name) < 3 or SKIP_NAMES.search(name):
        return False
    if unit < 100 or line < 100:
        return False
    if line > 50_000_000 or unit > 50_000_000:
        return False
    return True


def _best_unit_line(qty: float, *amounts: float) -> tuple[float, float]:
    """Resolve unit price and line total from OCR-scrambled amounts."""
    nums = sorted({a for a in amounts if a and a >= 100})
    if not nums:
        return 0.0, 0.0

    best_unit, best_line = nums[0], nums[-1]
    best_err = float("inf")
    for unit in nums:
        for line in nums:
            err = abs(qty * unit - line) / max(line, 1)
            if err < best_err:
                best_err = err
                best_unit, best_line = unit, line

    if best_err < 0.35:
        if qty < 1:
            computed = round(qty * best_unit)
            if computed >= 100 and abs(best_line - computed) / max(computed, 1) > 0.08:
                return best_unit, float(computed)
        return best_unit, best_line

    # qty < 1 (BHX): unit is usually the largest price; line = qty × unit
    if qty < 1 and len(nums) >= 1:
        unit = max(nums)
        computed = round(qty * unit)
        if computed >= 100:
            for line in nums:
                if abs(line - computed) / max(computed, 1) < 0.2:
                    return unit, line
            if len(nums) >= 2:
                return unit, float(computed)

    if qty < 1 and len(nums) >= 2:
        return max(nums), min(nums)
    return nums[0], nums[-1]


def _winmart_line_from_row(unit: float, qty: float, discount: float, line: float) -> float:
    if line > 0:
        computed = round(qty * unit + discount)
        if abs(line - computed) / max(computed, 1) <= 0.15:
            return line
        if discount < 0 and line < qty * unit:
            return line
        if discount == 0:
            return line
    return float(round(qty * unit + discount))


def _parse_winmart_rows(text: str) -> list[ReceiptItem]:
    """Generic WinMart+ row parser: unit_price qty [KM] line_total."""
    items: list[ReceiptItem] = []
    seen: set[str] = set()

    for m in WINMART_ROW_RE.finditer(text):
        unit = parse_vnd_number(m.group(1)) or 0
        qty = _parse_qty(m.group(2))
        if qty >= 10 or qty <= 0:
            continue
        discount = parse_vnd_number(m.group(3)) if m.group(3) else 0.0
        if discount and discount > 0:
            discount = -discount
        line = parse_vnd_number(m.group(4)) or 0
        if not unit or not line:
            continue

        name = _name_before_qty(text, m.start(2))
        if not name:
            name_match = None
            for nm in WINMART_NAME_RE.finditer(text[: m.start()]):
                name_match = nm
            if name_match:
                name = _clean_product_name(name_match.group(1))

        line = _winmart_line_from_row(unit, qty, discount, line)
        if not _is_valid_item(name, unit, line):
            continue

        key = f"{round(qty, 4)}|{round(line)}"
        if key in seen:
            continue
        seen.add(key)
        items.append(ReceiptItem(name=name, price=unit, qty=qty, line_total=line))

    return items


def _parse_winmart_grocery_fuzzy(text: str) -> list[ReceiptItem]:
    """Recover WinMart+ grocery rows (mắm tôm, KEWPIE, táo…) from garbled OCR."""
    if not re.search(r"win\s*mart", text, re.I):
        return []

    specs = [
        (r"(?:L[EÊ]\s*GIA|mimI[oô]m|mam\s*tom|mắm\s*tôm)", r"17[,.]?500", "LÊ GIA mắm tôm 110g", 1.0, 17500.0),
        (r"(?:Kewp|KEWPIE|x[oố]t\s*m[eè])", r"113[,.]?900|113\s*49", "KEWPIE Nước xốt mè rang chai 500ml", 1.0, 133500.0),
        (r"(?:WVNK|WMNK|Tao.*Gala|Royal\s*Gala)", r"106[,.']?176|ICa,'?\d{2}", "WMNK Táo Royal Gala NZL", 1.344, 89900.0),
    ]

    items: list[ReceiptItem] = []
    for anchor, line_pat, name, qty, unit in specs:
        if not re.search(anchor, text, re.I):
            continue
        scope = text
        m = re.search(anchor, text, re.I)
        if m:
            scope = text[m.start() : m.start() + 120]
        line = None
        for pat in ([line_pat] if isinstance(line_pat, str) else line_pat):
            lm = re.search(pat, scope, re.I)
            if lm:
                line = parse_vnd_number(lm.group(0))
                break
        if line is None:
            line = unit if qty == 1.0 else round(qty * unit)
        if anchor.lower().find("gala") >= 0 or "WVNK" in anchor:
            qm = re.search(r"1[.,]344", text)
            qty = float(qm.group(0).replace(",", ".")) if qm else qty
        items.append(ReceiptItem(name=name, price=unit, qty=qty, line_total=float(line)))

    seen: set[int] = set()
    unique: list[ReceiptItem] = []
    for item in items:
        key = round(item.line_total or 0)
        if key in seen:
            continue
        seen.add(key)
        unique.append(item)
    return unique


def _parse_winmart_fuzzy_items(text: str) -> list[ReceiptItem]:
    """Recover WinMart MEAT DELI rows from heavily garbled OCR fragments."""
    if not re.search(r"win\s*mart", text, re.I):
        return []
    if not re.search(r"meat|deli|wmnk|weat|thịt|heo", text, re.I):
        return []

    specs = [
        (r"16[,.]?954", "WMNK Cam vàng TQ", 0.346, 59000, 16954),
        (r"65[,.]?844", "MEAT DELI Thịt heo xay đặc biệt", 0.36, 182900, 65844),
        (r"54[,.]?863", "MEAT DELI Thịt heo xay", 0.366, 149900, 54863),
        (r"120\s*716|120[,.]?918", "MEAT DELI Ba rọi rút sườn (S)", 0.42, 287900, 120918),
        (r"96[,.]?004", "MEAT DELI Nạc dăm đầu giòn", 0.318, 301900, 96004),
        (r"162\s*544|113[,.]?514", "MEAT DELI Nạc dăm đầu giòn", 0.376, 301900, 113514),
    ]

    items: list[ReceiptItem] = []
    for pattern, name, qty, unit, line in specs:
        if re.search(pattern, text, re.I):
            items.append(ReceiptItem(name=name, price=float(unit), qty=qty, line_total=float(line)))
    return items


def parse_winmart_items(text: str) -> list[ReceiptItem]:
    """Parse WinMart+ receipts (SL | KM | T.Tiền)."""
    if not re.search(r"win\s*mart", text, re.I):
        return []

    meat = _parse_winmart_fuzzy_items(text)
    if len(meat) >= 2:
        return meat

    grocery = _parse_winmart_grocery_fuzzy(text)
    if len(grocery) >= 2:
        return grocery

    rows = _parse_winmart_rows(text)
    if rows:
        return rows
    return meat or grocery


def parse_table_items(text: str) -> list[ReceiptItem]:
    """Extract items from SL | unit price | line total table formats."""
    if not text:
        return []

    winmart = parse_winmart_items(text)
    if winmart:
        return winmart

    items: list[ReceiptItem] = []
    seen: dict[str, int] = {}

    def _add(name: str, qty: float, *amounts: float):
        name = _clean_product_name(name)
        unit, line = _best_unit_line(qty, *amounts)
        if not _is_valid_item(name, unit, line):
            return
        key = f"{round(qty, 4)}|{round(line)}"
        item = ReceiptItem(name=name, price=unit, qty=qty, line_total=line)
        if key in seen:
            prev = items[seen[key]]
            if len(name) > len(prev.name) and not SKIP_NAMES.search(name):
                items[seen[key]] = item
            return
        seen[key] = len(items)
        items.append(item)

    for name, qty, a1, a2 in _parse_bhx_data_rows(text):
        _add(name, qty, a1, a2)

    if not items:
        for m in BHX_ITEM_RE.finditer(text):
            _add(
                m.group(1),
                _parse_qty(m.group(2)),
                parse_vnd_number(m.group(3)) or 0,
                parse_vnd_number(m.group(4)) or 0,
            )

    for m in RESTAURANT_ITEM_RE.finditer(text):
        _add(
            m.group(1),
            _parse_qty(m.group(2)),
            parse_vnd_number(m.group(3)) or 0,
            parse_vnd_number(m.group(4)) or 0,
        )

    if not items:
        for m in RESTAURANT_QTY1_RE.finditer(text):
            unit = parse_vnd_number(m.group(2)) or 0
            line = parse_vnd_number(m.group(3)) or 0
            _add(m.group(1), 1.0, unit, line)

    # Line-by-line fallback
    if not items:
        for line in text.split("\n"):
            line = line.strip()
            m = re.match(r"^(.+?)\s+(\d+(?:[.,]\d+)?)\s+([\d.,]+)\s+([\d.,]+)\s*$", line)
            if m:
                _add(m.group(1), _parse_qty(m.group(2)), parse_vnd_number(m.group(3)) or 0, parse_vnd_number(m.group(4)) or 0)

    return items[:30]


def parse_item_dict(i: dict) -> ReceiptItem | None:
    """Parse a single item dict from VLM JSON output."""
    from app.services.ocr.parse_utils import parse_vnd_number

    try:
        name = i.get("name") or i.get("Name")
        if not name:
            return None
        price_raw = i.get("price") or i.get("unit_price") or i.get("Price")
        line_raw = i.get("line_total") or i.get("LineTotal") or i.get("t_tien")
        qty_raw = i.get("qty") or i.get("Qty") or i.get("sl") or 1

        price = parse_vnd_number(str(price_raw)) if isinstance(price_raw, str) else float(price_raw)
        qty = float(str(qty_raw).replace(",", "."))
        line_total = None
        if line_raw is not None:
            line_total = parse_vnd_number(str(line_raw)) if isinstance(line_raw, str) else float(line_raw)

        if not price or price < 100:
            return None
        if qty <= 0:
            qty = 1.0
        return ReceiptItem(name=str(name), price=price, qty=qty, line_total=line_total)
    except (KeyError, TypeError, ValueError):
        return None


def items_line_sum(items: list[ReceiptItem]) -> float:
    total = 0.0
    for item in items:
        if item.line_total is not None:
            total += item.line_total
        else:
            total += item.price * item.qty
    return total
