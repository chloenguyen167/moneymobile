"""Notification deduplication and transaction creation."""

from datetime import datetime, timedelta

from rapidfuzz import fuzz
from sqlalchemy import and_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import Transaction, TransactionSource
from app.schemas import NotificationFieldsIn


async def find_duplicate(
    db: AsyncSession,
    user_id: int,
    amount: float,
    merchant: str | None,
    tx_time: datetime | None,
    window_minutes: int = 5,
) -> Transaction | None:
    if not tx_time:
        tx_time = datetime.utcnow()

    start = tx_time - timedelta(minutes=window_minutes)
    end = tx_time + timedelta(minutes=window_minutes)

    result = await db.execute(
        select(Transaction).where(
            Transaction.user_id == user_id,
            Transaction.amount == amount,
            Transaction.created_at >= start,
            Transaction.created_at <= end,
        )
    )
    candidates = result.scalars().all()

    for tx in candidates:
        if merchant and tx.merchant_name:
            sim = fuzz.token_sort_ratio(merchant.lower(), tx.merchant_name.lower()) / 100
            if sim >= 0.7:
                return tx
        elif not merchant or not tx.merchant_name:
            return tx

    return None


async def merge_notification_with_ocr(
    db: AsyncSession,
    existing: Transaction,
    merchant: str | None,
) -> Transaction:
    if merchant and (not existing.merchant_name or len(merchant) > len(existing.merchant_name or "")):
        existing.merchant_name = merchant
    return existing
