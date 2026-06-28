"""Gmail email parsing for iOS transaction capture (Phase 3)."""

import base64
import logging
import re
from datetime import date, datetime
from typing import Optional

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import EmailConnection, Transaction
from app.schemas import OcrResult, TransactionCreate
from app.services.classify.pipeline import classify_transaction
from app.services.notification import find_duplicate
from app.services.transactions import save_transaction

logger = logging.getLogger(__name__)

# Known VN bank/wallet email senders
EMAIL_SENDERS = {
    "vietcombank.com.vn": "Vietcombank",
    "vietinbank.vn": "VietinBank",
    "techcombank.com.vn": "Techcombank",
    "mbbank.com.vn": "MB Bank",
    "tpb.vn": "TPBank",
    "acb.com.vn": "ACB",
    "momo.vn": "MoMo",
    "zalopay.vn": "ZaloPay",
}

AMOUNT_PATTERNS = [
    re.compile(r"(?P<sign>[+-])?\s*(?P<amount>[\d.,]+)\s*(?:VND|đ|vnđ)", re.I),
    re.compile(r"(?:số tiền|amount|gia tri)[:\s]*(?P<amount>[\d.,]+)", re.I),
    re.compile(r"(?P<amount>[\d.,]+)\s*đ\b", re.I),
]


def parse_email_body(subject: str, body: str, sender: str) -> Optional[dict]:
    """Extract transaction fields from bank email — no raw body stored."""
    merchant = _sender_to_merchant(sender)
    text = f"{subject}\n{body}"

    amount = None
    sign = "-"
    for pattern in AMOUNT_PATTERNS:
        match = pattern.search(text)
        if match:
            raw = match.group("amount").replace(",", "").replace(".", "")
            try:
                amount = float(raw)
                if match.groupdict().get("sign"):
                    sign = match.group("sign")
                break
            except ValueError:
                continue

    if amount is None or sign == "+":
        return None

    return {"amount": amount, "merchant": merchant, "sender": sender}


def _sender_to_merchant(sender: str) -> str:
    sender_lower = sender.lower()
    for domain, name in EMAIL_SENDERS.items():
        if domain in sender_lower:
            return name
    return sender.split("@")[-1].split(".")[0].title()


async def sync_user_emails(db: AsyncSession, user_id: int, max_messages: int = 20) -> list[Transaction]:
    result = await db.execute(
        select(EmailConnection).where(
            EmailConnection.user_id == user_id,
            EmailConnection.is_active.is_(True),
        )
    )
    conn = result.scalar_one_or_none()
    if not conn or not conn.refresh_token:
        return []

    messages = await _fetch_gmail_messages(conn.refresh_token, max_messages)
    created = []

    for msg in messages:
        parsed = parse_email_body(msg["subject"], msg["body"], msg["from"])
        if not parsed:
            continue

        duplicate = await find_duplicate(
            db, user_id, parsed["amount"], parsed["merchant"], msg.get("date")
        )
        if duplicate:
            continue

        ocr = OcrResult(
            merchant=parsed["merchant"],
            total_amount=parsed["amount"],
            transaction_date=msg.get("date", date.today()),
        )
        classification = await classify_transaction(db, user_id, ocr, amount=parsed["amount"])

        tx = await save_transaction(
            db,
            user_id,
            TransactionCreate(
                merchant_name=parsed["merchant"],
                amount=parsed["amount"],
                category_id=classification.category_id,
                source="email",
                transaction_date=ocr.transaction_date,
                confidence=classification.confidence,
                classification_reason=classification.reason,
            ),
        )
        created.append(tx)

    conn.last_sync_at = datetime.utcnow()
    return created


async def _fetch_gmail_messages(refresh_token: str, max_messages: int) -> list[dict]:
    from app.config import settings

    if not settings.gmail_client_id or not settings.gmail_client_secret:
        logger.warning("Gmail credentials not configured")
        return []

    try:
        from google.oauth2.credentials import Credentials
        from googleapiclient.discovery import build

        creds = Credentials(
            token=None,
            refresh_token=refresh_token,
            token_uri="https://oauth2.googleapis.com/token",
            client_id=settings.gmail_client_id,
            client_secret=settings.gmail_client_secret,
        )
        service = build("gmail", "v1", credentials=creds, cache_discovery=False)

        # Search recent emails from known senders
        domains = " OR ".join(f"from:{d}" for d in EMAIL_SENDERS)
        query = f"({domains}) newer_than:7d"

        list_resp = service.users().messages().list(userId="me", q=query, maxResults=max_messages).execute()
        messages = list_resp.get("messages", [])

        results = []
        for msg_ref in messages:
            msg = service.users().messages().get(userId="me", id=msg_ref["id"], format="full").execute()
            headers = {h["name"]: h["value"] for h in msg.get("payload", {}).get("headers", [])}
            body = _extract_body(msg.get("payload", {}))
            results.append(
                {
                    "subject": headers.get("Subject", ""),
                    "from": headers.get("From", ""),
                    "body": body[:2000],
                    "date": _parse_email_date(headers.get("Date", "")),
                }
            )
        return results
    except Exception as exc:
        logger.error("Gmail fetch failed: %s", exc)
        return []


def _extract_body(payload: dict) -> str:
    if payload.get("body", {}).get("data"):
        return base64.urlsafe_b64decode(payload["body"]["data"]).decode("utf-8", errors="ignore")
    for part in payload.get("parts", []):
        if part.get("mimeType") == "text/plain" and part.get("body", {}).get("data"):
            return base64.urlsafe_b64decode(part["body"]["data"]).decode("utf-8", errors="ignore")
    return ""


def _parse_email_date(date_str: str) -> date:
    try:
        from email.utils import parsedate_to_datetime

        return parsedate_to_datetime(date_str).date()
    except Exception:
        return date.today()
