"""Optional on-box OCR engines (EasyOCR). Install: pip install -r requirements-ocr.txt"""

import logging

logger = logging.getLogger(__name__)

_engine = None
_engine_checked = False


def is_local_ocr_available() -> bool:
    global _engine_checked, _engine
    if _engine_checked:
        return _engine is not None

    _engine_checked = True
    try:
        import easyocr  # noqa: F401

        _engine = "easyocr"
        logger.info("Local OCR engine: EasyOCR (vi+en)")
    except ImportError:
        _engine = None
        logger.debug("EasyOCR not installed — local OCR disabled")
    return _engine is not None


def run_local_ocr(image_bytes: bytes) -> str:
    """Run EasyOCR on receipt image. Raises if engine unavailable."""
    if not is_local_ocr_available():
        raise RuntimeError(
            "Local OCR not available. Install: pip install -r requirements-ocr.txt"
        )

    import easyocr
    import numpy as np
    import cv2

    arr = np.frombuffer(image_bytes, np.uint8)
    img = cv2.imdecode(arr, cv2.IMREAD_COLOR)
    if img is None:
        raise ValueError("Cannot decode image for local OCR")

    reader = easyocr.Reader(["vi", "en"], gpu=False, verbose=False)
    lines = reader.readtext(img, detail=0, paragraph=True)
    return "\n".join(line.strip() for line in lines if line and line.strip())
