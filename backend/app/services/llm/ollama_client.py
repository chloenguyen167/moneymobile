"""Ollama client — native /api/chat (think:false) for Qwen3 text + Qwen3-VL."""

from __future__ import annotations

import base64
import io
import json
import logging

import httpx
from PIL import Image

from app.config import settings

logger = logging.getLogger(__name__)


def ollama_available() -> bool:
    return bool(settings.ollama_enabled and settings.ollama_base_url.strip())


def _native_base() -> str:
    """http://host:11434 — strip accidental /v1 suffix."""
    url = settings.ollama_base_url.rstrip("/")
    if url.endswith("/v1"):
        url = url[:-3].rstrip("/")
    return url


def _http_timeout(seconds: int) -> httpx.Timeout:
    return httpx.Timeout(seconds, connect=15.0)


def _format_exc(exc: Exception) -> str:
    text = str(exc).strip()
    if text:
        return f"{type(exc).__name__}: {text}"
    return type(exc).__name__


def prepare_vision_image(image_bytes: bytes) -> bytes:
    """Downscale + JPEG compress before VLM to reduce latency on local Ollama."""
    max_edge = max(512, settings.ollama_vl_max_edge_px)
    try:
        with Image.open(io.BytesIO(image_bytes)) as img:
            img = img.convert("RGB")
            w, h = img.size
            longest = max(w, h)
            if longest > max_edge:
                scale = max_edge / longest
                img = img.resize((int(w * scale), int(h * scale)), Image.Resampling.LANCZOS)
            buf = io.BytesIO()
            img.save(buf, format="JPEG", quality=85, optimize=True)
            out = buf.getvalue()
            logger.debug(
                "Ollama vision image prepared: %dx%d -> %d bytes (from %d bytes)",
                w,
                h,
                len(out),
                len(image_bytes),
            )
            return out
    except Exception as exc:
        logger.warning("Vision image prepare failed, using original: %s", _format_exc(exc))
        return image_bytes


def parse_json_content(content: str) -> dict | None:
    content = (content or "").strip()
    if content.startswith("```"):
        parts = content.split("```")
        if len(parts) >= 2:
            content = parts[1]
            if content.startswith("json"):
                content = content[4:]
    content = content.strip()
    try:
        data = json.loads(content)
    except json.JSONDecodeError:
        start = content.find("{")
        end = content.rfind("}")
        if start < 0 or end <= start:
            return None
        try:
            data = json.loads(content[start : end + 1])
        except json.JSONDecodeError:
            return None
    return data if isinstance(data, dict) else None


def _message_content(data: dict) -> str | None:
    """Parse native /api/chat or OpenAI-compat response content."""
    message = data.get("message")
    if isinstance(message, dict):
        content = message.get("content")
        if isinstance(content, str) and content.strip():
            return content
    try:
        content = data["choices"][0]["message"].get("content")
        if isinstance(content, str) and content.strip():
            return content
    except (KeyError, IndexError, TypeError, AttributeError):
        pass
    return None


async def chat_json(prompt: str, num_predict: int = 2048) -> dict | None:
    """Text chat → JSON via native Ollama /api/chat (think disabled for Qwen3)."""
    if not ollama_available():
        return None

    # /no_think + think:false — Qwen3 otherwise burns the whole timeout thinking
    user_prompt = prompt if "/no_think" in prompt else f"/no_think\n{prompt}"
    payload = {
        "model": settings.ollama_llm_model,
        "messages": [{"role": "user", "content": user_prompt}],
        "stream": False,
        "format": "json",
        "think": False,
        "options": {
            "temperature": 0.1,
            "num_predict": max(512, num_predict),
        },
    }
    timeout = settings.ollama_llm_timeout_seconds

    try:
        async with httpx.AsyncClient(timeout=_http_timeout(timeout)) as client:
            resp = await client.post(f"{_native_base()}/api/chat", json=payload)
            resp.raise_for_status()
            content = _message_content(resp.json())
            if not content:
                logger.warning("Ollama LLM returned empty content")
                return None
            data = parse_json_content(content)
            if data is None:
                logger.warning("Ollama LLM returned non-JSON content: %s", content[:200])
            return data
    except Exception as exc:
        logger.warning(
            "Ollama LLM (%s) failed after %ss: %s",
            settings.ollama_llm_model,
            timeout,
            _format_exc(exc),
        )
        return None


async def chat_vision_json(
    prompt: str,
    image_bytes: bytes,
    hint: str | None = None,
) -> dict | None:
    """Multimodal chat → JSON via native Ollama /api/chat + images[]."""
    if not ollama_available():
        return None

    prepared = prepare_vision_image(image_bytes)
    b64 = base64.b64encode(prepared).decode()
    text = prompt if "/no_think" in prompt else f"/no_think\n{prompt}"
    if hint:
        text = f"{text}\n\nOCR hint (may contain errors — prefer the image):\n{hint[:3000]}"

    payload = {
        "model": settings.ollama_vl_model,
        "messages": [
            {
                "role": "user",
                "content": text,
                "images": [b64],
            }
        ],
        "stream": False,
        "format": "json",
        "think": False,
        "options": {
            "temperature": 0.1,
            "num_predict": 2048,
        },
    }
    timeout = settings.ollama_vl_timeout_seconds

    try:
        async with httpx.AsyncClient(timeout=_http_timeout(timeout)) as client:
            resp = await client.post(f"{_native_base()}/api/chat", json=payload)
            resp.raise_for_status()
            content = _message_content(resp.json())
            if not content:
                logger.warning("Ollama VL returned empty content")
                return None
            data = parse_json_content(content)
            if data is None:
                logger.warning("Ollama VL returned non-JSON content: %s", content[:200])
            return data
    except Exception as exc:
        logger.warning(
            "Ollama VL (%s) failed after %ss: %s",
            settings.ollama_vl_model,
            timeout,
            _format_exc(exc),
        )
        return None
