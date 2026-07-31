"""Vintern-1B VLM — Transformers AutoModel.chat() (primary) or HTTP API (fallback)."""

import asyncio
import base64
import json
import logging
import re
from datetime import date

import httpx

from app.config import settings
from app.schemas import OcrResult, ReceiptItem
from app.services.ocr.items_parser import parse_item_dict
from app.services.ocr.prompts import RECEIPT_OCR_PROMPT
from app.services.ocr.vintern_pipeline import (
    is_vintern_pipeline_available,
    run_vintern_pipeline,
)

logger = logging.getLogger(__name__)

VINTERN_PROMPT = RECEIPT_OCR_PROMPT


def is_vintern_available() -> bool:
    """Vintern usable via local pipeline or remote HTTP API."""
    if settings.vintern_use_local_pipeline and is_vintern_pipeline_available():
        return True
    return bool(settings.vintern_api_url)


def _build_prompt(raw_text: str | None) -> str:
    prompt = VINTERN_PROMPT
    if raw_text:
        prompt += f"\n\nOCR hint:\n{raw_text}"
    return prompt


def _run_vintern_pipeline_sync(
    image_bytes: bytes,
    raw_text: str | None,
    *,
    original_bytes: bytes | None = None,
) -> OcrResult:
    from app.services.ocr.enrich import enrich_from_easyocr
    from app.services.ocr.local_ocr import is_local_ocr_available, run_local_ocr

    ocr_hint = raw_text
    if not ocr_hint and original_bytes and is_local_ocr_available():
        try:
            ocr_hint = run_local_ocr(original_bytes)
        except Exception:
            pass

    generated = run_vintern_pipeline(image_bytes, _build_prompt(ocr_hint))
    result = _content_to_ocr_result(generated, generated)
    return enrich_from_easyocr(result, image_bytes, original_bytes=original_bytes)


async def run_vintern(
    image_bytes: bytes,
    raw_text: str | None = None,
    *,
    original_bytes: bytes | None = None,
) -> OcrResult | None:
    if settings.vintern_use_local_pipeline and is_vintern_pipeline_available():
        try:
            return await asyncio.to_thread(
                _run_vintern_pipeline_sync, image_bytes, raw_text, original_bytes=original_bytes
            )
        except Exception as exc:
            logger.warning("Vintern local inference failed: %s", exc)

    if settings.vintern_api_url:
        return await _run_vintern_http(image_bytes, raw_text)

    return None


def _image_mime(image_bytes: bytes) -> str:
    if image_bytes[:8] == b"\x89PNG\r\n\x1a\n":
        return "image/png"
    if image_bytes[:2] == b"\xff\xd8":
        return "image/jpeg"
    return "image/jpeg"


def _vintern_base_url() -> str:
    url = settings.vintern_api_url.rstrip("/")
    if not url.endswith("/v1"):
        url = f"{url}/v1"
    return url


async def _run_vintern_http(
    image_bytes: bytes,
    raw_text: str | None = None,
) -> OcrResult | None:
    b64 = base64.b64encode(image_bytes).decode()
    user_text = _build_prompt(raw_text)

    payload = {
        "model": settings.vintern_model_name,
        "messages": [
            {
                "role": "user",
                "content": [
                    {"type": "text", "text": user_text},
                    {"type": "image_url", "image_url": {"url": f"data:{_image_mime(image_bytes)};base64,{b64}"}},
                ],
            }
        ],
        "max_tokens": 1024,
        "temperature": 0.1,
    }

    headers = {"Content-Type": "application/json"}
    if settings.vintern_api_key:
        headers["Authorization"] = f"Bearer {settings.vintern_api_key}"

    try:
        async with httpx.AsyncClient(timeout=settings.vintern_timeout_seconds) as client:
            resp = await client.post(
                f"{_vintern_base_url()}/chat/completions",
                headers=headers,
                json=payload,
            )
            resp.raise_for_status()
            content = resp.json()["choices"][0]["message"]["content"]
    except Exception as exc:
        logger.warning("Vintern HTTP failed: %s", exc)
        return None

    return _content_to_ocr_result(content, content)


def _content_to_ocr_result(content: str, raw_content: str | None = None) -> OcrResult:
    raw = raw_content or content
    try:
        data = _parse_json_response(content)
        if data:
            result = _to_ocr_result(data, full_raw=raw)
            if not result.raw_text:
                result = result.model_copy(update={"raw_text": raw})
            return result
    except (json.JSONDecodeError, ValueError) as exc:
        logger.debug("Vintern JSON parse failed, using text parser: %s", exc)

    return _text_to_ocr_result(raw)


def _text_to_ocr_result(text: str) -> OcrResult:
    from app.services.ocr.parse_utils import (
        estimate_text_confidence,
        parse_amount,
        parse_date,
        parse_items,
        parse_merchant,
    )

    amount = parse_amount(text)
    dt = parse_date(text)
    return OcrResult(
        merchant=parse_merchant(text),
        items=parse_items(text),
        total_amount=amount,
        transaction_date=dt,
        ocr_track_used="vintern",
        ocr_confidence=estimate_text_confidence(text, amount, dt),
        raw_text=text,
    )


def _normalize_keys(data: dict) -> dict:
    out: dict = {}
    for k, v in data.items():
        key = k.strip().lower().replace(" ", "_")
        out[key] = v
    aliases = {
        "store": "merchant",
        "total": "total_amount",
        "transactiondate": "transaction_date",
        "receipttext": "receipt_text",
        "confidence": "confidence",
    }
    for src, dst in aliases.items():
        if dst not in out and src in out:
            out[dst] = out[src]
    if "merchant" not in out and "store" in out:
        out["merchant"] = out["store"]
    if "total_amount" not in out and "total" in out:
        out["total_amount"] = out["total"]
    return out


def _parse_item(i: dict) -> ReceiptItem | None:
    return parse_item_dict(i)


def _parse_json_response(content: str) -> dict:
    content = content.strip()
    if "```" in content:
        for block in re.findall(r"```(?:json)?\s*([\s\S]*?)```", content, re.I):
            block = block.strip()
            if block.startswith("{"):
                try:
                    data = json.loads(block)
                    if isinstance(data, dict):
                        return _normalize_keys(data)
                except json.JSONDecodeError:
                    pass
        content = content.split("```")[1]
        if content.startswith("json"):
            content = content[4:]

    try:
        data = json.loads(content.strip())
        return _normalize_keys(data) if isinstance(data, dict) else {}
    except json.JSONDecodeError:
        pass

    # Truncated JSON — extract fields individually
    partial: dict = {}
    merchant_match = re.search(r'"merchant"\s*:\s*"([^"]+)"', content, re.I)
    if merchant_match:
        partial["merchant"] = merchant_match.group(1)
    total_match = re.search(r'"total_amount"\s*:\s*(\d+)', content, re.I)
    if total_match:
        partial["total_amount"] = int(total_match.group(1))
    date_match = re.search(r'"transaction_date"\s*:\s*"(\d{4}-\d{2}-\d{2})"', content, re.I)
    if date_match:
        partial["transaction_date"] = date_match.group(1)

    items = []
    for m in re.finditer(
        r'\{"name"\s*:\s*"([^"]+)"\s*,\s*"price"\s*:\s*(\d+)\s*,\s*"qty"\s*:\s*([\d.]+)\s*,\s*"line_total"\s*:\s*(\d+)\}',
        content,
        re.I,
    ):
        items.append(
            {
                "name": m.group(1),
                "price": int(m.group(2)),
                "qty": float(m.group(3)),
                "line_total": int(m.group(4)),
            }
        )
    if items:
        partial["items"] = items
    return _normalize_keys(partial) if partial else {}


def _sanitize_items(items: list[ReceiptItem]) -> list[ReceiptItem]:
    """Drop VLM spam: duplicate generic names, impossible qty, too many rows."""
    if not items:
        return items

    cleaned: list[ReceiptItem] = []
    for item in items:
        if item.qty > 10 or item.qty <= 0:
            continue
        if item.price < 1000 or (item.line_total or 0) < 1000:
            continue
        if item.line_total and item.qty > 0:
            ratio = abs(item.line_total - item.price * item.qty) / max(item.line_total, 1)
            if ratio > 0.6 and item.qty < 2:
                item = item.model_copy(update={"line_total": round(item.price * item.qty)})
        cleaned.append(item)

    if len(cleaned) > 8:
        names = {i.name.strip().lower() for i in cleaned}
        if len(names) <= 2:
            # Keep rows with distinct line totals
            seen: set[int] = set()
            deduped = []
            for item in cleaned:
                key = round(item.line_total or item.price * item.qty)
                if key in seen:
                    continue
                seen.add(key)
                deduped.append(item)
            cleaned = deduped[:8]

    return cleaned[:8]


def _to_ocr_result(data: dict, full_raw: str = "") -> OcrResult:
    from app.services.ocr.parse_utils import parse_vnd_number

    items = []
    raw_items = data.get("items") or data.get("Items") or []
    for i in raw_items:
        if not isinstance(i, dict):
            continue
        parsed = _parse_item(i)
        if parsed:
            items.append(parsed)
    items = _sanitize_items(items)

    tx_date = None
    date_raw = data.get("transaction_date") or data.get("transactiondate")
    if date_raw and str(date_raw) not in ("YYYY-MM-DD", "null", ""):
        try:
            tx_date = date.fromisoformat(str(date_raw)[:10])
        except ValueError:
            pass

    total_raw = data.get("total_amount") or data.get("total")
    if isinstance(total_raw, str):
        total = parse_vnd_number(total_raw)
    elif total_raw is not None:
        total = float(total_raw)
    else:
        total = None

    if total and total > 50_000_000:
        total = None

    confidence = float(data.get("confidence", 0.85))
    receipt_txt = data.get("receipt_text") or data.get("receipttext") or data.get("raw_text") or ""
    raw_text = f"{receipt_txt}\n{full_raw}" if receipt_txt and full_raw and receipt_txt not in full_raw else (receipt_txt or full_raw)
    return OcrResult(
        merchant=data.get("merchant"),
        items=items,
        total_amount=total,
        transaction_date=tx_date,
        ocr_track_used="vintern",
        ocr_confidence=confidence,
        raw_text=raw_text,
    )
