import base64
import json
import logging
import re
from datetime import date

import httpx

from app.config import settings
from app.schemas import PaymentScreenshotExtract

logger = logging.getLogger(__name__)

PAYMENT_SCREENSHOT_PROMPT = """Extract a single payment transaction from this Vietnamese banking or e-wallet screenshot.
Return JSON only with keys:
- merchant
- total_amount
- transaction_date (YYYY-MM-DD or null)
- payment_source
- description
- reference_code
- confidence

Rules:
1. This is NOT a receipt with many items — one transfer amount only.
2. total_amount = số tiền chuyển đầy đủ gần chữ VND/đ, dạng số nguyên VND.
   Example: "14,350,000 VND" → 14350000 (NOT 4350, NOT 14350).
   NEVER use: mã giao dịch (661V00924158ASXP), số tài khoản, OTP, ngày giờ, số dư.
3. merchant = TÊN NGƯỜI NHẬN (payee/receiver), e.g. TRAN THI THANH.
   NEVER append UI chips: "Đã lưu", "Saved".
   NEVER use: "Cảm ơn…", quảng cáo miễn phí, "Giao dịch thành công", tên ngân hàng gửi.
4. description = nội dung chuyển khoản (memo), not the thank-you banner.
5. reference_code = mã giao dịch alphanumeric.
6. Ignore UI labels, ads, balances, decorative text.
7. If a field is missing, return null.
"""


def _image_mime(image_bytes: bytes) -> str:
    if image_bytes[:8] == b"\x89PNG\r\n\x1a\n":
        return "image/png"
    if image_bytes[:2] == b"\xff\xd8":
        return "image/jpeg"
    return "image/jpeg"


async def run_payment_smart_extract(
    image_bytes: bytes,
    raw_text_hint: str | None = None,
) -> PaymentScreenshotExtract | None:
    if settings.gemini_api_key:
        result = await _gemini_extract(image_bytes, raw_text_hint)
        if result:
            return result

    if settings.openai_api_key:
        result = await _openai_extract(image_bytes, raw_text_hint)
        if result:
            return result

    return None


async def _gemini_extract(
    image_bytes: bytes,
    raw_text_hint: str | None,
) -> PaymentScreenshotExtract | None:
    url = (
        f"https://generativelanguage.googleapis.com/v1beta/models/"
        f"{settings.gemini_model}:generateContent?key={settings.gemini_api_key}"
    )
    b64 = base64.b64encode(image_bytes).decode()
    parts: list[dict] = [{"text": PAYMENT_SCREENSHOT_PROMPT}]
    if raw_text_hint:
        parts.append({"text": f"OCR hint:\n{raw_text_hint}"})
    parts.append(
        {"inline_data": {"mime_type": _image_mime(image_bytes), "data": b64}}
    )

    try:
        async with httpx.AsyncClient(timeout=60) as client:
            resp = await client.post(
                url,
                json={
                    "contents": [{"parts": parts}],
                    "generationConfig": {"responseMimeType": "application/json"},
                },
            )
            resp.raise_for_status()
            text = resp.json()["candidates"][0]["content"]["parts"][0]["text"]
            payload = json.loads(text)
    except Exception as exc:
        logger.warning("Gemini payment screenshot extract failed: %s", exc)
        return None

    return _json_to_extract(payload, track="payment_gemini")


async def _openai_extract(
    image_bytes: bytes,
    raw_text_hint: str | None,
) -> PaymentScreenshotExtract | None:
    b64 = base64.b64encode(image_bytes).decode()
    content: list[dict] = [{"type": "text", "text": PAYMENT_SCREENSHOT_PROMPT}]
    if raw_text_hint:
        content.append({"type": "text", "text": f"OCR hint:\n{raw_text_hint}"})
    content.append(
        {"type": "image_url", "image_url": {"url": f"data:image/jpeg;base64,{b64}"}}
    )

    try:
        async with httpx.AsyncClient(timeout=60) as client:
            resp = await client.post(
                "https://api.openai.com/v1/chat/completions",
                headers={"Authorization": f"Bearer {settings.openai_api_key}"},
                json={
                    "model": "gpt-4o-mini",
                    "messages": [{"role": "user", "content": content}],
                    "response_format": {"type": "json_object"},
                },
            )
            resp.raise_for_status()
            payload = json.loads(resp.json()["choices"][0]["message"]["content"])
    except Exception as exc:
        logger.warning("OpenAI payment screenshot extract failed: %s", exc)
        return None

    return _json_to_extract(payload, track="payment_openai")


def _json_to_extract(payload: dict, track: str) -> PaymentScreenshotExtract:
    tx_date = None
    raw_date = payload.get("transaction_date")
    if raw_date:
        tx_date = _parse_date_value(raw_date)

    amount = _parse_amount_value(payload.get("total_amount"))

    try:
        confidence = float(payload.get("confidence", 0.82))
    except (TypeError, ValueError):
        confidence = 0.82

    return PaymentScreenshotExtract(
        merchant=payload.get("merchant"),
        total_amount=amount,
        transaction_date=tx_date,
        payment_source=payload.get("payment_source"),
        description=payload.get("description"),
        reference_code=payload.get("reference_code"),
        ocr_track_used=track,
        ocr_confidence=confidence,
        raw_text=payload.get("raw_text"),
    )


def _parse_date_value(value: object) -> date | None:
    from datetime import date

    if value is None:
        return None

    raw = str(value).strip()
    if not raw:
        return None

    for candidate in (raw[:10], raw):
        try:
            return date.fromisoformat(candidate)
        except ValueError:
            pass

    match = re.search(r"(\d{2})/(\d{2})/(\d{4})", raw)
    if match:
        day, month, year = map(int, match.groups())
        try:
            return date(year, month, day)
        except ValueError:
            return None

    return None


def _parse_amount_value(value: object) -> float | None:
    if value is None:
        return None

    if isinstance(value, (int, float)):
        amount = float(value)
        if amount < 1000 or amount >= 100_000_000_000:
            return None
        return amount if amount > 0 else None

    raw = str(value).strip().lower()
    if not raw:
        return None

    # Reject alphanumeric txn ids mistaken for amounts
    if re.search(r"[a-z]", raw) and re.search(r"\d", raw):
        return None

    raw = raw.replace("vnd", "").replace("đ", "").replace("d", "")
    raw = raw.replace(" ", "")
    raw = raw.replace(",", "")
    raw = raw.replace(".", "")
    raw = raw.replace("+", "")

    try:
        amount = float(raw)
    except ValueError:
        return None

    if amount < 1000 or amount >= 100_000_000_000:
        return None
    return amount
