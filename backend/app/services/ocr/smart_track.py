"""Smart Track OCR — Phase 3: Vintern → Gemini → OpenAI → heuristic cascade."""

import base64
import json
import logging
from datetime import date

import httpx

from app.config import settings
from app.schemas import OcrResult, ReceiptItem
from app.services.ocr.vintern import run_vintern

logger = logging.getLogger(__name__)

SMART_PROMPT = """Extract receipt data from this Vietnamese receipt image/text.
Return JSON only with keys: merchant, items (array of {name, price, qty}), total_amount (number), transaction_date (YYYY-MM-DD), confidence (0-1).
If text hint is provided, use it to correct OCR errors especially Vietnamese diacritics."""


def _image_mime(image_bytes: bytes) -> str:
    if image_bytes[:8] == b"\x89PNG\r\n\x1a\n":
        return "image/png"
    if image_bytes[:2] == b"\xff\xd8":
        return "image/jpeg"
    if image_bytes[:4] == b"RIFF" and image_bytes[8:12] == b"WEBP":
        return "image/webp"
    return "image/jpeg"


async def run_smart_track(
    image_bytes: bytes,
    raw_text: str | None = None,
    end_to_end: bool = False,
) -> OcrResult:
    # 1. Vintern-1B self-host (preferred for Vietnamese)
    vintern_result = await run_vintern(image_bytes, raw_text if not end_to_end else None)
    if vintern_result and vintern_result.ocr_confidence >= settings.vintern_confidence_threshold:
        return vintern_result

    # 2. Gemini Flash fallback
    if settings.gemini_api_key:
        gemini = await _gemini_extract(image_bytes, raw_text, end_to_end)
        if gemini and gemini.ocr_confidence >= 0.7:
            gemini.ocr_track_used = "gemini"
            return gemini

    # 3. OpenAI fallback
    if settings.openai_api_key:
        openai_result = await _openai_extract(image_bytes, raw_text, end_to_end)
        if openai_result:
            openai_result.ocr_track_used = "openai"
            return openai_result

    # 4. Use low-confidence Vintern if available
    if vintern_result:
        return vintern_result

    return _heuristic_smart_fallback(raw_text, end_to_end)


async def _gemini_extract(image_bytes: bytes, raw_text: str | None, end_to_end: bool) -> OcrResult | None:
    b64 = base64.b64encode(image_bytes).decode()
    parts: list[dict] = [{"text": SMART_PROMPT}]
    if raw_text and not end_to_end:
        parts.append({"text": f"OCR hint:\n{raw_text}"})
    parts.append({"inline_data": {"mime_type": _image_mime(image_bytes), "data": b64}})

    url = (
        f"https://generativelanguage.googleapis.com/v1beta/models/"
        f"{settings.gemini_model}:generateContent?key={settings.gemini_api_key}"
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
            data = json.loads(text)
    except Exception as exc:
        logger.warning("Gemini OCR failed: %s", exc)
        return None

    return _json_to_ocr_result(data, track="gemini")


async def _openai_extract(image_bytes: bytes, raw_text: str | None, end_to_end: bool) -> OcrResult | None:
    b64 = base64.b64encode(image_bytes).decode()
    user_content: list[dict] = [{"type": "text", "text": SMART_PROMPT}]
    if raw_text and not end_to_end:
        user_content.append({"type": "text", "text": f"OCR hint:\n{raw_text}"})
    user_content.append({"type": "image_url", "image_url": {"url": f"data:image/jpeg;base64,{b64}"}})

    try:
        async with httpx.AsyncClient(timeout=60) as client:
            resp = await client.post(
                "https://api.openai.com/v1/chat/completions",
                headers={"Authorization": f"Bearer {settings.openai_api_key}"},
                json={
                    "model": "gpt-4o-mini",
                    "messages": [{"role": "user", "content": user_content}],
                    "response_format": {"type": "json_object"},
                },
            )
            resp.raise_for_status()
            data = json.loads(resp.json()["choices"][0]["message"]["content"])
    except Exception as exc:
        logger.warning("OpenAI OCR failed: %s", exc)
        return None

    return _json_to_ocr_result(data, track="openai")


def _json_to_ocr_result(data: dict, track: str) -> OcrResult:
    items = [ReceiptItem(**i) for i in data.get("items", []) if "name" in i and "price" in i]
    tx_date = None
    if data.get("transaction_date"):
        try:
            tx_date = date.fromisoformat(str(data["transaction_date"])[:10])
        except ValueError:
            pass
    return OcrResult(
        merchant=data.get("merchant"),
        items=items,
        total_amount=data.get("total_amount"),
        transaction_date=tx_date,
        ocr_track_used=track,
        ocr_confidence=float(data.get("confidence", 0.88)),
    )


def _heuristic_smart_fallback(raw_text: str | None, end_to_end: bool) -> OcrResult:
    from app.services.ocr.fast_track import _parse_amount, _parse_date, _parse_items, _parse_merchant

    text = raw_text or ""
    return OcrResult(
        merchant=_parse_merchant(text) if text else "Unknown Merchant",
        items=_parse_items(text) if text else [],
        total_amount=_parse_amount(text),
        transaction_date=_parse_date(text) or date.today(),
        ocr_track_used="smart",
        ocr_confidence=0.75 if text else 0.5,
        raw_text=text,
    )
