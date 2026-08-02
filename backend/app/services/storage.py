"""Persist uploaded receipt / payment screenshot images."""

from __future__ import annotations

import uuid
from pathlib import Path

from app.config import settings


def ensure_upload_dir() -> Path:
    root = Path(settings.upload_dir)
    root.mkdir(parents=True, exist_ok=True)
    return root


def save_transaction_image(user_id: int, image_bytes: bytes, filename: str | None = None) -> str:
    """Write bytes under uploads/{user_id}/{uuid}.ext and return relative path."""
    root = ensure_upload_dir()
    user_dir = root / str(user_id)
    user_dir.mkdir(parents=True, exist_ok=True)

    suffix = ".jpg"
    if filename and "." in filename:
        ext = filename.rsplit(".", 1)[-1].lower()
        if ext in {"jpg", "jpeg", "png", "webp", "heic"}:
            suffix = f".{ext if ext != 'jpeg' else 'jpg'}"

    rel = f"{user_id}/{uuid.uuid4().hex}{suffix}"
    path = root / rel
    path.write_bytes(image_bytes)
    return rel


def resolve_image_path(relative: str) -> Path | None:
    if not relative or ".." in relative:
        return None
    path = Path(settings.upload_dir) / relative
    if not path.is_file():
        return None
    return path
