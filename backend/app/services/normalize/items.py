import re

from app.schemas import OcrResult, ReceiptItem
from app.services.ocr.reference_correction import normalize_vietnamese

SIZE_RE = re.compile(r"(?P<value>\d+(?:[.,]\d+)?)\s*(?P<unit>kg|g|gr|ml|l|lit)\b")

NOISE_TOKENS = {
    "xx",
    "xxx",
    "happy",
    "vg",
    "vn",
    "viet",
    "sp",
    "hh",
}

DISCOUNT_KEYWORDS = [
    "uu dai",
    "uu dai the",
    "giam gia",
    "khuyen mai",
    "chiet khau",
    "voucher",
    "discount",
]

NON_PRODUCT_KEYWORDS = [
    "tong tien",
    "tong cong",
    "tam tinh",
    "thanh tien",
    "khach dua",
    "tien khach dua",
    "tien mat",
    "tien the",
    "tien thoi",
    "thoi lai",
    "can tra",
    "phai tra",
    "vat",
    "thue",
    "phi dich vu",
    "phi",
    "diem tich luy",
    "tich diem",
    "so tien tiet kiem",
    "tiet kiem",
    "voucher",
    "ma giam",
]

BRAND_KEYWORDS = {
    "vissan": "Vissan",
    "meatdeli": "MeatDeli",
    "cp": "CP",
    "vinamilk": "Vinamilk",
    "downy": "Downy",
    "donny": "Downy",
    "yakult": "Yakult",
    "dove": "Dove",
    "pantene": "Pantene",
    "headshoulders": "Head&Shoulders",
    "colgate": "Colgate",
    "milac": "Milac",
    "simply": "Simply",
}

CANONICAL_PHRASES: list[tuple[list[str], str]] = [
    (["thit heo xay", "heo xay"], "thit heo xay"),
    (["thit bo", "bo my", "bo xay"], "thit bo"),
    (["thit ga", "ga xay"], "thit ga"),
    (["cai thia"], "cai thia"),
    (["cai ngot"], "cai ngot"),
    (["rau muong"], "rau muong"),
    (["xa lach", "xalach"], "xa lach"),
    (["tao gala", "tao chile gala", "tao chile"], "tao gala"),
    (["cam sanh"], "cam sanh"),
    (["sua tuoi"], "sua tuoi"),
    (["sua chua"], "sua chua"),
    (["sua bot", "sua bau", "milac mom"], "sua bot"),
    (["mi goi", "mi an lien", "mi tom"], "mi goi"),
    (["nuoc xa vai", "nuoc xa", "nxv"], "nuoc xa vai"),
    (["chong nang", "dau nang"], "chong nang"),
]

ALIAS_PHRASES: list[tuple[list[str], str]] = [
    (["th heo xay", "thheo xay", "heo xay viet", "thit heo xay viet"], "thit heo xay"),
    (["th bo", "bo xay viet", "thit bo viet"], "thit bo"),
    (["th ga", "ga xay viet", "thit ga viet"], "thit ga"),
    (["srm tam", "sua r tam", "s tam"], "sua tam"),
    (["ddg", "dg goi", "d goi"], "dau goi"),
    (["k dr", "kem drg", "kem dg rang"], "kem danh rang"),
    (["c thia vg", "cai thia vg", "c thia"], "cai thia"),
    (["x lach", "xa lach", "xl"], "xa lach"),
    (["rm", "rau muong"], "rau muong"),
    (["tao chile gala baby", "tao gala baby"], "tao gala"),
    (["nxv", "n xv", "nuoc xa", "nuoc xa downy", "donny"], "nuoc xa vai"),
    (["mi", "mi an lien", "mi 3 mien", "hao hao", "omachi", "reeva"], "mi goi"),
    (["sua milac", "milac mom", "mom ht"], "sua bot"),
    (["dau nang", "kem chong nang", "sunscreen"], "chong nang"),
]


def _extract_size(text: str) -> tuple[float | None, str | None]:
    match = SIZE_RE.search(text)
    if not match:
        return None, None
    value = float(match.group("value").replace(",", "."))
    unit = match.group("unit")
    if unit == "gr":
        unit = "g"
    if unit == "lit":
        unit = "l"
    return value, unit


def _detect_brand(text: str) -> str | None:
    for keyword, brand in BRAND_KEYWORDS.items():
        if keyword in text.split() or keyword in text:
            return brand
    return None


def _canonicalize(text: str) -> str:
    for phrases, canonical in CANONICAL_PHRASES:
        if any(phrase in text for phrase in phrases):
            return canonical
    return text


def _resolve_aliases(text: str) -> str:
    resolved = text
    for aliases, canonical in ALIAS_PHRASES:
        if any(alias in resolved for alias in aliases):
            resolved = canonical
            break
    return re.sub(r"\s+", " ", resolved).strip()


def is_discount_line(item: ReceiptItem) -> bool:
    raw_name = item.raw_name or item.name
    normalized_name = item.normalized_name or normalize_vietnamese(raw_name)
    if item.price >= 0:
        return False
    return any(keyword in normalized_name for keyword in DISCOUNT_KEYWORDS)


def is_non_product_line(item: ReceiptItem) -> bool:
    raw_name = item.raw_name or item.name
    normalized_name = item.normalized_name or normalize_vietnamese(raw_name)
    compact_name = re.sub(r"\s+", " ", normalized_name).strip()

    if not compact_name:
        return True

    if any(keyword in compact_name for keyword in NON_PRODUCT_KEYWORDS):
        return True

    # Lines made entirely of payment/summary tokens are not purchasable items.
    tokens = compact_name.split()
    if tokens and all(
        token in {"tong", "tien", "cong", "khach", "dua", "thoi", "lai", "vat", "thue", "phi", "diem", "tich", "luy"}
        for token in tokens
    ):
        return True

    return False


def normalize_receipt_item(item: ReceiptItem) -> ReceiptItem:
    raw_name = item.raw_name or item.name
    normalized_name = normalize_vietnamese(raw_name)
    size_value, size_unit = _extract_size(normalized_name)
    brand = item.brand or _detect_brand(normalized_name)

    removed_tokens: list[str] = []
    tokens: list[str] = []
    for token in normalized_name.split():
        if token in NOISE_TOKENS:
            removed_tokens.append(token)
            continue
        if SIZE_RE.fullmatch(token):
            removed_tokens.append(token)
            continue
        tokens.append(token)

    cleaned = " ".join(tokens).strip()
    if brand:
        cleaned = re.sub(rf"\b{re.escape(normalize_vietnamese(brand))}\b", "", cleaned).strip()
        cleaned = re.sub(r"\s+", " ", cleaned).strip()

    alias_resolved = _resolve_aliases(cleaned)
    canonical_name = _canonicalize(alias_resolved)

    return item.model_copy(
        update={
            "raw_name": raw_name,
            "normalized_name": normalized_name,
            "canonical_name": canonical_name or normalized_name,
            "brand": brand,
            "size_value": size_value,
            "size_unit": size_unit,
            "removed_tokens": removed_tokens or item.removed_tokens,
        }
    )


def normalize_ocr_result(result: OcrResult) -> OcrResult:
    # LLM already structured items from raw OCR — do not rewrite/filter with keyword rules
    if result.ocr_track_used == "fast_llm":
        preserved = [
            item.model_copy(
                update={
                    "raw_name": item.raw_name or item.name,
                    "normalized_name": item.normalized_name or item.name,
                    "canonical_name": item.canonical_name or item.name,
                }
            )
            for item in result.items
        ]
        return result.model_copy(update={"items": preserved})

    normalized_items = [normalize_receipt_item(item) for item in result.items]
    filtered_items = [
        item
        for item in normalized_items
        if not is_discount_line(item) and not is_non_product_line(item)
    ]
    return result.model_copy(update={"items": filtered_items})
