"""Firebase Cloud Messaging push notifications."""

import logging
from typing import Optional

from app.config import settings

logger = logging.getLogger(__name__)

_firebase_app = None


def _get_firebase_app():
    global _firebase_app
    if _firebase_app is not None:
        return _firebase_app
    if not settings.firebase_credentials_path:
        return None
    try:
        import firebase_admin
        from firebase_admin import credentials

        cred = credentials.Certificate(settings.firebase_credentials_path)
        _firebase_app = firebase_admin.initialize_app(cred)
        return _firebase_app
    except Exception as exc:
        logger.warning("Firebase init failed: %s", exc)
        return None


async def send_push_to_tokens(
    tokens: list[str],
    title: str,
    body: str,
    data: Optional[dict] = None,
) -> int:
    """Send FCM push. Returns count of successful sends."""
    if not tokens or not settings.fcm_enabled:
        return 0

    app = _get_firebase_app()
    if app is None:
        return 0

    try:
        from firebase_admin import messaging

        message = messaging.MultipartMessage(
            notification=messaging.Notification(title=title, body=body),
            data={k: str(v) for k, v in (data or {}).items()},
            tokens=tokens,
        )
        response = messaging.send_each_for_multicast(message)
        logger.info("FCM sent: success=%d failure=%d", response.success_count, response.failure_count)
        return response.success_count
    except Exception as exc:
        logger.error("FCM send failed: %s", exc)
        return 0
