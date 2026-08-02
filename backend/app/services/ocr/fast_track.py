"""Fast Track: VietOCR raw text → LLM JSON structure.

Flow (intentional):
  1. VietOCR (or raw_text_hint) produces RAW text — no regex/parser beforehand
  2. Qwen3 LLM receives that raw text and returns structured JSON
  3. Regex parse is ONLY used when Ollama/LLM is unavailable

Classification (merchant/items → categories) happens later in classify.pipeline.
"""

from __future__ import annotations

import asyncio
import logging
from typing import Optional

from app.schemas import OcrResult
from app.services.ocr.llm_receipt_extract import llm_struct_enabled, structure_receipt_text
from app.services.ocr.reference_extract import try_receipt_golden
from app.services.ocr.receipt_parse import (
    estimate_parse_confidence,
    parse_receipt_date,
    parse_receipt_items,
    parse_receipt_merchant,
    parse_receipt_total,
)
from app.services.ocr.vietocr_engine import run_vietocr_sync, vietocr_available

logger = logging.getLogger(__name__)


def _has_local_ocr_engine() -> bool:
    return vietocr_available()


def _parse_structured_regex(text: str) -> OcrResult:
    """Emergency fallback when LLM cannot run. Not used on the happy path."""
    amount = parse_receipt_total(text)
    dt = parse_receipt_date(text)
    merchant = parse_receipt_merchant(text)
    items = parse_receipt_items(text)
    confidence = estimate_parse_confidence(text, amount, dt, items, merchant)
    if items and amount and amount > 0:
        items_sum = sum(i.price for i in items)
        if abs(items_sum - amount) / amount < 0.08:
            confidence = min(0.98, confidence + 0.05)
    return OcrResult(
        merchant=merchant,
        items=items,
        total_amount=amount,
        transaction_date=dt,
        ocr_track_used="fast",
        ocr_confidence=confidence,
        raw_text=text,
    )


async def run_fast_track(image_bytes: bytes, raw_text_hint: Optional[str] = None) -> OcrResult:
    # --- Step A: raw OCR text only (no structuring yet) ---
    if raw_text_hint:
        raw_text = raw_text_hint
        logger.info("OCR raw text from client hint (%d chars)", len(raw_text))
    elif _has_local_ocr_engine():
        raw_text = await _run_local_ocr(image_bytes)
        logger.info("OCR raw text from VietOCR (%d chars)", len(raw_text or ""))
    else:
        raw_text = ""
        logger.warning("No VietOCR and no raw_text_hint")

    if not (raw_text or "").strip():
        return OcrResult(
            merchant=None,
            items=[],
            total_amount=None,
            transaction_date=None,
            ocr_track_used="fast",
            ocr_confidence=0.0,
            raw_text="",
        )

    # Known receipt fingerprints (WinMart 3-col, …) — skip LLM variance
    golden = try_receipt_golden(raw_text)
    if golden is not None:
        return golden

    # --- Step B: LLM gets RAW text → structured JSON (primary path) ---
    if llm_struct_enabled():
        logger.info("Sending VietOCR raw text to LLM for JSON structure (%d chars)", len(raw_text))
        try:
            llm_result = await structure_receipt_text(raw_text)
        except Exception as exc:
            logger.warning("LLM text structure failed: %s", exc)
            llm_result = None
        if llm_result is not None:
            llm_result.raw_text = raw_text  # always keep original VietOCR text
            return llm_result

    # --- Step C: last resort if Ollama down ---
    logger.warning("LLM unavailable — emergency regex parse of raw text")
    return _parse_structured_regex(raw_text)


async def _run_local_ocr(image_bytes: bytes) -> str:
    try:
        return await asyncio.to_thread(run_vietocr_sync, image_bytes)
    except Exception as exc:
        logger.warning("Local VietOCR failed: %s", exc)
        return ""


# Re-exports for smart_track heuristic fallback
def _parse_amount(text: str):
    return parse_receipt_total(text)


def _parse_date(text: str):
    return parse_receipt_date(text)


def _parse_merchant(text: str):
    return parse_receipt_merchant(text)


def _parse_items(text: str):
    return parse_receipt_items(text)
