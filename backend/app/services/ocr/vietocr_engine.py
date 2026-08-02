"""Local Vietnamese OCR via VietOCR + OpenCV region detection.

VietOCR (https://github.com/pbcquoc/vietocr) recognizes cropped text.
Supermarket receipts are multi-column — we detect word/segment boxes,
cluster into rows, and OCR segments separately so Giá/SL/T.Tiền stay intact.
"""

from __future__ import annotations

import logging
import threading

import cv2
import numpy as np
from PIL import Image

from app.config import settings

logger = logging.getLogger(__name__)

_predictor_lock = threading.Lock()
_predictor = None
_predictor_failed = False


def vietocr_available() -> bool:
    if not settings.vietocr_enabled or _predictor_failed:
        return False
    try:
        import vietocr  # noqa: F401
        import pkg_resources  # noqa: F401
    except ImportError:
        return False
    return True


def _resolve_device() -> str:
    configured = (settings.vietocr_device or "").strip().lower()
    if configured:
        return configured
    try:
        import torch

        if torch.backends.mps.is_available():
            return "mps"
        if torch.cuda.is_available():
            return "cuda"
    except Exception:
        pass
    return "cpu"


def _get_predictor():
    global _predictor, _predictor_failed
    if _predictor is not None:
        return _predictor
    if _predictor_failed:
        return None

    with _predictor_lock:
        if _predictor is not None:
            return _predictor
        if _predictor_failed:
            return None
        try:
            from vietocr.tool.config import Cfg
            from vietocr.tool.predictor import Predictor

            model_name = settings.vietocr_model
            config = Cfg.load_config_from_name(model_name)
            config["cnn"]["pretrained"] = False
            config["device"] = _resolve_device()
            config["predictor"]["beamsearch"] = False
            logger.info(
                "Loading VietOCR model=%s device=%s (first run may download weights)",
                model_name,
                config["device"],
            )
            _predictor = Predictor(config)
            logger.info("VietOCR ready")
            return _predictor
        except Exception as exc:
            _predictor_failed = True
            logger.exception("Failed to load VietOCR: %s", exc)
            return None


def _load_bgr(image_bytes: bytes) -> np.ndarray:
    arr = np.frombuffer(image_bytes, dtype=np.uint8)
    img = cv2.imdecode(arr, cv2.IMREAD_COLOR)
    if img is None:
        raise ValueError("Cannot decode image for VietOCR")

    min_w = max(1000, min(settings.vietocr_max_image_width, 1400))
    max_w = max(min_w, settings.vietocr_max_image_width)
    h, w = img.shape[:2]
    if w < min_w:
        scale = min_w / w
        img = cv2.resize(img, (int(w * scale), int(h * scale)), interpolation=cv2.INTER_CUBIC)
    elif w > max_w:
        scale = max_w / w
        img = cv2.resize(img, (int(w * scale), int(h * scale)), interpolation=cv2.INTER_AREA)
    return img


def _binarize(gray: np.ndarray) -> np.ndarray:
    blur = cv2.GaussianBlur(gray, (3, 3), 0)
    adaptive = cv2.adaptiveThreshold(
        blur, 255, cv2.ADAPTIVE_THRESH_GAUSSIAN_C, cv2.THRESH_BINARY_INV, 31, 11
    )
    _, otsu = cv2.threshold(blur, 0, 255, cv2.THRESH_BINARY_INV + cv2.THRESH_OTSU)
    binary = cv2.bitwise_or(adaptive, otsu)
    binary = cv2.morphologyEx(
        binary, cv2.MORPH_OPEN, cv2.getStructuringElement(cv2.MORPH_RECT, (2, 2))
    )
    return binary


def detect_text_boxes(image_bgr: np.ndarray) -> list[tuple[int, int, int, int]]:
    """Detect word/segment boxes (not full-width lines) for multi-column receipts."""
    gray = cv2.cvtColor(image_bgr, cv2.COLOR_BGR2GRAY)
    h, w = gray.shape[:2]
    binary = _binarize(gray)

    kernel_w = max(10, w // 70)
    kernel = cv2.getStructuringElement(cv2.MORPH_RECT, (kernel_w, 2))
    connected = cv2.morphologyEx(binary, cv2.MORPH_CLOSE, kernel, iterations=1)
    connected = cv2.dilate(
        connected, cv2.getStructuringElement(cv2.MORPH_RECT, (3, 1)), iterations=1
    )

    contours, _ = cv2.findContours(connected, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    boxes: list[tuple[int, int, int, int]] = []
    min_h = max(9, h // 180)
    max_h = h // 7
    min_area = max(60, (w * h) // 25000)

    for cnt in contours:
        x, y, bw, bh = cv2.boundingRect(cnt)
        if bh < min_h or bh > max_h or bw < 6:
            continue
        if bw * bh < min_area:
            continue
        aspect = bw / max(bh, 1)
        if aspect < 0.25:
            continue
        pad_x, pad_y = 2, 2
        x0 = max(0, x - pad_x)
        y0 = max(0, y - pad_y)
        x1 = min(w, x + bw + pad_x)
        y1 = min(h, y + bh + pad_y)
        boxes.append((x0, y0, x1 - x0, y1 - y0))

    boxes.sort(key=lambda b: (b[1] + b[3] // 2, b[0]))
    return boxes[:300]


def _cluster_rows(
    boxes: list[tuple[int, int, int, int]], image_h: int
) -> list[list[tuple[int, int, int, int]]]:
    if not boxes:
        return []
    rows: list[dict] = []
    for box in boxes:
        x, y, bw, bh = box
        cy = y + bh // 2
        tol = max(10, bh * 0.65, image_h // 120)
        if not rows or abs(cy - rows[-1]["cy"]) > tol:
            rows.append({"cy": cy, "boxes": [box]})
        else:
            rows[-1]["boxes"].append(box)
            rows[-1]["cy"] = int(
                np.mean([b[1] + b[3] // 2 for b in rows[-1]["boxes"]])
            )
    for row in rows:
        row["boxes"].sort(key=lambda b: b[0])
    return [row["boxes"] for row in rows]


def _predict_crop(predictor, image_bgr: np.ndarray, box: tuple[int, int, int, int]) -> str:
    x, y, bw, bh = box
    crop = image_bgr[y : y + bh, x : x + bw]
    if crop.size == 0 or crop.shape[1] < 16:
        return ""
    if float(np.mean(crop)) > 252:
        return ""
    pil = Image.fromarray(cv2.cvtColor(crop, cv2.COLOR_BGR2RGB))
    try:
        return (predictor.predict(pil) or "").strip()
    except Exception as exc:
        logger.debug("VietOCR crop failed: %s", exc)
        return ""


def _recognize_row(
    predictor, image_bgr: np.ndarray, boxes: list[tuple[int, int, int, int]]
) -> str:
    h, w = image_bgr.shape[:2]
    if not boxes:
        return ""

    xs = [b[0] for b in boxes]
    ys = [b[1] for b in boxes]
    xe = [b[0] + b[2] for b in boxes]
    ye = [b[1] + b[3] for b in boxes]
    x0, y0 = max(0, min(xs) - 2), max(0, min(ys) - 2)
    x1, y1 = min(w, max(xe) + 2), min(h, max(ye) + 2)
    row_w = x1 - x0

    if len(boxes) >= 2 and row_w > w * 0.55:
        parts = [_predict_crop(predictor, image_bgr, b) for b in boxes]
        parts = [p for p in parts if p]
        return "  ".join(parts)

    return _predict_crop(predictor, image_bgr, (x0, y0, x1 - x0, y1 - y0))


def _is_noise_line(text: str) -> bool:
    compact = re_sub_noise(text)
    if len(compact) >= 12 and compact.isdigit():
        return True
    if compact.count("0") > 8 and set(compact) <= set("01"):
        return True
    return False


def re_sub_noise(text: str) -> str:
    return (
        text.replace(" ", "")
        .replace("|", "")
        .replace(",", "")
        .replace(".", "")
        .replace("-", "")
    )


def run_vietocr_sync(image_bytes: bytes) -> str:
    """Detect regions + recognize with VietOCR. Returns multiline raw text."""
    if not vietocr_available():
        return ""

    predictor = _get_predictor()
    if predictor is None:
        return ""

    image_bgr = _load_bgr(image_bytes)
    boxes = detect_text_boxes(image_bgr)
    rows = _cluster_rows(boxes, image_bgr.shape[0])

    if not rows:
        pil = Image.fromarray(cv2.cvtColor(image_bgr, cv2.COLOR_BGR2RGB))
        try:
            return (predictor.predict(pil) or "").strip()
        except Exception as exc:
            logger.warning("VietOCR whole-image predict failed: %s", exc)
            return ""

    lines: list[str] = []
    for row_boxes in rows:
        text = _recognize_row(predictor, image_bgr, row_boxes)
        if not text or _is_noise_line(text):
            continue
        lines.append(text)

    return "\n".join(lines)


def detect_text_line_boxes(image_bgr: np.ndarray) -> list[tuple[int, int, int, int]]:
    """Back-compat: merged row boxes."""
    boxes = detect_text_boxes(image_bgr)
    rows = _cluster_rows(boxes, image_bgr.shape[0])
    merged: list[tuple[int, int, int, int]] = []
    h, w = image_bgr.shape[:2]
    for row in rows:
        xs = [b[0] for b in row]
        ys = [b[1] for b in row]
        xe = [b[0] + b[2] for b in row]
        ye = [b[1] + b[3] for b in row]
        x0, y0 = max(0, min(xs)), max(0, min(ys))
        x1, y1 = min(w, max(xe)), min(h, max(ye))
        merged.append((x0, y0, x1 - x0, y1 - y0))
    return merged
