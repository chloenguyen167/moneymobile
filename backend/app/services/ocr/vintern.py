"""Vintern-1B VLM client — self-hosted via OpenAI-compatible API (vLLM/RunPod/Modal)."""

import base64
import json
import logging
from datetime import date

import httpx

from app.config import settings
from app.schemas import OcrResult, ReceiptItem

logger = logging.getLogger(__name__)

VINTERN_PROMPT = """Bạn là hệ thống OCR hóa đơn Việt Nam. Chỉ đọc nội dung trên tờ hóa đơn giấy trong ảnh (bỏ qua giao diện app/UI nếu có).
Trả JSON duy nhất (không markdown), keys chính xác:
{
  "merchant": "tên cửa hàng",
  "items": [{"name": "...", "price": 55000, "qty": 1}],
  "total_amount": 55000,
  "transaction_date": "YYYY-MM-DD",
  "confidence": 0.0-1.0
}
Chú ý dấu tiếng Việt và số tiền VND."""


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


async def run_vintern(
    image_bytes: bytes,
    raw_text: str | None = None,
) -> OcrResult | None:
    if not settings.vintern_api_url:
        return None

    b64 = base64.b64encode(image_bytes).decode()
    user_text = VINTERN_PROMPT
    if raw_text:
        user_text += f"\n\nOCR hint:\n{raw_text}"

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
            data = _parse_json_response(content)
    except Exception as exc:
        logger.warning("Vintern OCR failed: %s", exc)
        return None

    return _to_ocr_result(data)


def _normalize_keys(data: dict) -> dict:
    """Accept Merchant/total_amount variants from VLM output."""
    out: dict = {}
    for k, v in data.items():
        key = k.strip().lower().replace(" ", "_")
        out[key] = v
    if "merchant" not in out and "store" in out:
        out["merchant"] = out["store"]
    if "total_amount" not in out and "total" in out:
        out["total_amount"] = out["total"]
    return out


def _parse_json_response(content: str) -> dict:
    content = content.strip()
    if content.startswith("```"):
        content = content.split("```")[1]
        if content.startswith("json"):
            content = content[4:]
    data = json.loads(content.strip())
    return _normalize_keys(data) if isinstance(data, dict) else {}


def _to_ocr_result(data: dict) -> OcrResult:
    items = []
    for i in data.get("items", []):
        try:
            qty = max(1, int(round(float(i.get("qty", 1)))))
            items.append(ReceiptItem(name=i["name"], price=float(i["price"]), qty=qty))
        except (KeyError, TypeError, ValueError):
            continue

    tx_date = None
    if data.get("transaction_date"):
        try:
            tx_date = date.fromisoformat(str(data["transaction_date"])[:10])
        except ValueError:
            pass

    confidence = float(data.get("confidence", 0.85))
    return OcrResult(
        merchant=data.get("merchant"),
        items=items,
        total_amount=float(data["total_amount"]) if data.get("total_amount") else None,
        transaction_date=tx_date,
        ocr_track_used="vintern",
        ocr_confidence=confidence,
    )
