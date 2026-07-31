"""Receipt image preprocessing before OCR."""

import logging

import cv2
import numpy as np

logger = logging.getLogger(__name__)

MAX_DIMENSION = 2048
JPEG_QUALITY = 92


def preprocess_receipt_image(image_bytes: bytes) -> bytes:
    """
    Improve OCR accuracy: resize, denoise, contrast (CLAHE), sharpen.
    Returns original bytes if decoding fails.
    """
    try:
        arr = np.frombuffer(image_bytes, np.uint8)
        img = cv2.imdecode(arr, cv2.IMREAD_COLOR)
        if img is None:
            return image_bytes

        h, w = img.shape[:2]
        if max(h, w) > MAX_DIMENSION:
            scale = MAX_DIMENSION / max(h, w)
            img = cv2.resize(img, None, fx=scale, fy=scale, interpolation=cv2.INTER_AREA)

        img = cv2.fastNlMeansDenoisingColored(img, None, 6, 6, 7, 21)

        lab = cv2.cvtColor(img, cv2.COLOR_BGR2LAB)
        l_channel, a_channel, b_channel = cv2.split(lab)
        clahe = cv2.createCLAHE(clipLimit=2.5, tileGridSize=(8, 8))
        l_channel = clahe.apply(l_channel)
        img = cv2.cvtColor(cv2.merge([l_channel, a_channel, b_channel]), cv2.COLOR_LAB2BGR)

        kernel = np.array([[0, -1, 0], [-1, 5, -1], [0, -1, 0]], dtype=np.float32)
        img = cv2.filter2D(img, -1, kernel)

        ok, buf = cv2.imencode(".jpg", img, [cv2.IMWRITE_JPEG_QUALITY, JPEG_QUALITY])
        if not ok:
            return image_bytes
        return buf.tobytes()
    except Exception as exc:
        logger.warning("Image preprocessing failed, using original: %s", exc)
        return image_bytes
